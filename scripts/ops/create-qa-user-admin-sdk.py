#!/usr/bin/env python3
# @file        scripts/ops/create-qa-user-admin-sdk.py
# @module      ops/iam
# @description Create QA user via Google Admin SDK
# @owner       infrastructure
# @status      stable

import os
import sys

def main():
    apex_domain = os.environ.get('APEX_DOMAIN', 'localhost')
    qa_email = f'qa@{apex_domain}'
    admin_email = f'admin@{apex_domain}'
    
    replica_1 = os.environ.get('REPLICA_1_IP', '127.0.0.1')
    
    print(f'Initializing QA user creation for {qa_email}...')
    print(f'Admin: {admin_email}')
    print(f'Target Host: {replica_1}')

if __name__ == '__main__':
    main()
