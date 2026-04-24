#!/usr/bin/env python3
# @file        apps/agent-registry/test_discovery.py
# @module      agent-registry/tests
# @description Tests for agent discovery, search, and ranking
# @owner       Phase 4 — Ecosystem & Autonomy
# @status      active

import unittest

from discovery import DiscoveryEngine
from packages import get_store


class TestDiscovery(unittest.TestCase):
    def setUp(self):
        self.engine = DiscoveryEngine()
        self.store = get_store()
        self.store.packages = {}
        self.store.index = {}

        self.store.publish(
            "kushin77/test-agent",
            "1.0.0",
            {
                "namespace": "kushin77/test-agent",
                "description": "High quality testing agent",
                "author": "Kushnir",
                "category": "testing",
                "capabilities": ["testing", "reporting"],
                "reputation_score": 80,
                "install_count": 1000,
                "rating": 4.5,
            },
            b"content",
        )
        self.store.publish(
            "kushin77/sec-bot",
            "1.1.0",
            {
                "namespace": "kushin77/sec-bot",
                "description": "Security scanner for repo",
                "author": "Kushnir",
                "category": "security",
                "capabilities": ["scan", "reporting"],
                "reputation_score": 90,
                "install_count": 500,
                "rating": 4.8,
            },
            b"content",
        )
        self.store.publish(
            "untrusted/bad-agent",
            "0.1.0",
            {
                "namespace": "untrusted/bad-agent",
                "description": "Low reputation agent",
                "author": "Unknown",
                "category": "testing",
                "capabilities": ["testing"],
                "reputation_score": 20,
                "install_count": 10,
                "rating": 2.0,
            },
            b"content",
        )

    def test_ranking(self):
        agents = [
            {"reputation_score": 100, "install_count": 1000, "rating": 5.0},
            {"reputation_score": 50, "install_count": 100, "rating": 3.0},
        ]

        ranked = self.engine.rank(agents)

        self.assertEqual(ranked[0]["reputation_score"], 100)
        self.assertGreater(ranked[0]["rank_score"], ranked[1]["rank_score"])

    def test_search_keywords(self):
        results = self.engine.search("security")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["namespace"], "kushin77/sec-bot")

        results = self.engine.search("kushin77")
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0]["namespace"], "kushin77/sec-bot")

    def test_filter_public(self):
        all_agents = [package["metadata"] for package in self.store.list_all_latest()]
        public = self.engine.filter_public(all_agents)

        self.assertEqual(len(public), 2)
        for agent in public:
            self.assertGreaterEqual(agent["reputation_score"], 50)

    def test_category_filter(self):
        all_agents = [package["metadata"] for package in self.store.list_all_latest()]
        sec_agents = self.engine.filter_by_category(all_agents, "security")

        self.assertEqual(len(sec_agents), 1)
        self.assertEqual(sec_agents[0]["category"], "security")


if __name__ == "__main__":
    unittest.main()#!/usr/bin/env python3
# @file        apps/agent-registry/test_discovery.py
# @module      agent-registry/tests
# @description Tests for agent discovery, search and ranking
# @owner       Phase 4 — Ecosystem & Autonomy
# @status      active

import unittest
import sys
import importlib.util
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

def load_module(module_name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(module_name, APP_DIR / file_name)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module

packages_module = load_module("packages", "packages.py")
sys.modules["packages"] = packages_module
discovery_module = load_module("discovery", "discovery.py")

DiscoveryEngine = discovery_module.DiscoveryEngine
get_store = packages_module.get_store

class TestDiscovery(unittest.TestCase):
    def setUp(self):
        self.engine = DiscoveryEngine()
        self.store = get_store()
        # Reset store for each test
        self.store.packages = {}
        self.store.index = {}

        # Add some mock agents
        self.store.publish(
            "kushin77/test-agent", "1.0.0",
            {"namespace": "kushin77/test-agent", "description": "High quality testing agent", 
             "category": "testing", "reputation_score": 80, "install_count": 1000, "rating": 4.5},
            b"content"
        )
        self.store.publish(
            "kushin77/sec-bot", "1.1.0",
            {"namespace": "kushin77/sec-bot", "description": "Security scanner for repo", 
             "category": "security", "reputation_score": 90, "install_count": 500, "rating": 4.8},
            b"content"
        )
        self.store.publish(
            "untrusted/bad-agent", "0.1.0",
            {"namespace": "untrusted/bad-agent", "description": "Low reputation agent", 
             "category": "testing", "reputation_score": 20, "install_count": 10, "rating": 2.0},
            b"content"
        )

    def test_ranking(self):
        agents = [
            {"reputation_score": 100, "install_count": 1000, "rating": 5.0},
            {"reputation_score": 50, "install_count": 100, "rating": 3.0}
        ]
        ranked = self.engine.rank(agents)
        self.assertEqual(ranked[0]["reputation_score"], 100)
        self.assertGreater(ranked[0]["rank_score"], ranked[1]["rank_score"])

    def test_search_keywords(self):
        # Search for 'security'
        results = self.engine.search("security")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["namespace"], "kushin77/sec-bot")

        # Search for 'testing' (should find 2 but rank higher the better one)
        results = self.engine.search("testing")
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0]["namespace"], "kushin77/test-agent")

    def test_filter_public(self):
        all_agents = [p["metadata"] for p in self.store.list_all_latest()]
        public = self.engine.filter_public(all_agents)
        # Should filter out untrusted/bad-agent (reputation 20)
        self.assertEqual(len(public), 2)
        for agent in public:
            self.assertGreaterEqual(agent["reputation_score"], 50)

    def test_category_filter(self):
        all_agents = [p["metadata"] for p in self.store.list_all_latest()]
        sec_agents = self.engine.filter_by_category(all_agents, "security")
        self.assertEqual(len(sec_agents), 1)
        self.assertEqual(sec_agents[0]["category"], "security")

if __name__ == "__main__":
    unittest.main()
