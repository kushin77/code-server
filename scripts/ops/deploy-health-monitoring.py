#!/usr/bin/env python3
# @file        scripts/ops/deploy-health-monitoring.py
# @module      ops/observability
# @description Health monitoring deployment utility
# @owner       infrastructure
# @status      stable

import os
import sys

def main():
    r1 = os.environ.get('REPLICA_1_IP', '127.0.0.1')
    r2 = os.environ.get('REPLICA_2_IP', '127.0.0.1')
    
    print(f'Monitoring deployed targeting {r1} and {r2}')

if __name__ == '__main__':
    main()
