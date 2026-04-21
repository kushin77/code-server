#!/usr/bin/env python3
# @file        services/test_terminal_output_optimizer.py
# @module      terminal-output/dlp-tests
# @description Unit tests for terminal output DLP blocking and redaction.
#

from __future__ import annotations

import importlib.util
import pathlib
import sys
import types
import unittest


def load_optimizer_module():
    websockets_module = types.ModuleType('websockets')
    websockets_server_module = types.ModuleType('websockets.server')
    websockets_server_module.WebSocketServerProtocol = object
    websockets_module.server = websockets_server_module
    sys.modules['websockets'] = websockets_module
    sys.modules['websockets.server'] = websockets_server_module

    module_path = pathlib.Path(__file__).with_name('terminal-output-optimizer.py')
    spec = importlib.util.spec_from_file_location('terminal_output_optimizer', module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError('unable to load terminal output optimizer module')

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TerminalOutputOptimizerDlpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_optimizer_module()

    def test_blocks_cli_secret_arguments(self):
        optimizer = self.module.TerminalBatchOptimizer()

        batch = optimizer.add_update('deploy --password super-secret')
        self.assertIsNone(batch)

        flushed = optimizer.flush()
        self.assertIsNotNone(flushed)
        assert flushed is not None
        self.assertEqual(flushed['updates'][0]['data'], self.module.BLOCKED_OUTPUT_PLACEHOLDER)
        self.assertEqual(flushed['updates'][0]['dlp_action'], 'block')
        self.assertIn('credential_assignment', flushed['updates'][0]['dlp_reason'])
        self.assertEqual(flushed['dlp']['blocked_updates'], 1)

    def test_redacts_inline_pii(self):
        optimizer = self.module.TerminalBatchOptimizer()

        optimizer.add_update('user alice@example.com connected from 203.0.113.10')
        flushed = optimizer.flush()
        self.assertIsNotNone(flushed)
        assert flushed is not None
        self.assertEqual(
            flushed['updates'][0]['data'],
            'user [EMAIL-REDACTED] connected from [IP-REDACTED]',
        )
        self.assertEqual(flushed['updates'][0]['dlp_action'], 'redact')
        self.assertEqual(flushed['dlp']['redacted_updates'], 1)

    def test_metrics_include_dlp_counts(self):
        optimizer = self.module.TerminalBatchOptimizer()

        optimizer.add_update('deploy --token abcdefghijk')
        optimizer.add_update('alice@example.com')
        optimizer.flush()

        metrics = optimizer.get_metrics()
        self.assertEqual(metrics.blocked_updates, 1)
        self.assertEqual(metrics.redacted_updates, 1)


if __name__ == '__main__':
    unittest.main()