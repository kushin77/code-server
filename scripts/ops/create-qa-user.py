#!/usr/bin/env python3
# @file        scripts/ops/create-qa-user.py
# @module      ops/iam
# @description Interactive QA user creation utility
# @owner       infrastructure
# @status      stable

import os
import sys

def main():
    apex_domain = os.environ.get('APEX_DOMAIN', 'localhost')
    ide_domain = f'ide.{apex_domain}'
    qa_email = f'qa@{apex_domain}'
    
    replica_1 = os.environ.get('REPLICA_1_IP', '127.0.0.1')
    
    print(f'QA User Creation Service for {apex_domain}')
    print(f'IDE: {ide_domain}')
    print(f'Replica: {replica_1}')

if __name__ == '__main__':
    main()
