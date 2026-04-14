#!/usr/bin/env python3
"""
Phase 26-B: Analytics Aggregator Service
Continuously aggregates metrics from Prometheus and stores in ClickHouse.

Responsibilities:
- Collect metrics from Prometheus every 30 seconds
- Aggregate hourly statistics (min/max/avg/p50/p99/)
- Calculate cost per-organization
- Store results in ClickHouse for real-time dashboards
"""

import json
import logging
import os
import sys
import time
from datetime import datetime, timedelta
from typing import Any, Dict, List

import psycopg2
import requests
from clickhouse_driver import Client as ClickHouseClient

# ════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════

# Logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Environment variables
PROMETHEUS_URL = os.getenv('PROMETHEUS_URL', 'http://localhost:9090')
CLICKHOUSE_HOST = os.getenv('CLICKHOUSE_HOST', 'localhost')
CLICKHOUSE_PORT = int(os.getenv('CLICKHOUSE_PORT', 9000))
CLICKHOUSE_DB = os.getenv('CLICKHOUSE_DB', 'code_server_analytics')
CLICKHOUSE_USER = os.getenv('CLICKHOUSE_USER', 'default')
CLICKHOUSE_PASSWORD = os.getenv('CLICKHOUSE_PASSWORD', '')

POSTGRES_HOST = os.getenv('POSTGRES_HOST', 'localhost')
POSTGRES_PORT = int(os.getenv('POSTGRES_PORT', 5432))
POSTGRES_DB = os.getenv('POSTGRES_DB', 'code_server')
POSTGRES_USER = os.getenv('POSTGRES_USER', 'code_server_user')
POSTGRES_PASSWORD = os.getenv('POSTGRES_PASSWORD', '')

# Aggregation interval
AGGREGATION_INTERVAL = 30  # seconds
HOURLY_AGGREGATION_INTERVAL = 3600  # 1 hour

# Cost configuration (per tier)
COST_CONFIG = {
    'free': {
        'base': 0,
        'per_api_call': 0.0001,  # $0.0001 per 10 calls
        'per_gb_storage': 0,
    },
    'pro': {
        'base': 10,  # $10/month base
        'per_api_call': 0.00005,  # $0.00005 per 10 calls
        'per_gb_storage': 0.5,
    },
    'enterprise': {
        'base': 100,  # $100/month base
        'per_api_call': 0.00001,  # $0.00001 per 10 calls
        'per_gb_storage': 0.1,
    },
}


# ════════════════════════════════════════════════════════════════════════
# ClickHouse Connection Manager
# ════════════════════════════════════════════════════════════════════════

class ClickHouseManager:
    def __init__(self):
        self.client = None
        self.connect()

    def connect(self):
        """Connect to ClickHouse cluster"""
        try:
            self.client = ClickHouseClient(
                host=CLICKHOUSE_HOST,
                port=CLICKHOUSE_PORT,
                database=CLICKHOUSE_DB,
                user=CLICKHOUSE_USER,
                password=CLICKHOUSE_PASSWORD,
                settings={
                    'max_insert_threads': 4,
                    'insert_quorum': 2,
                }
            )
            logger.info('Connected to ClickHouse')
            self.create_tables()
        except Exception as e:
            logger.error(f'Failed to connect to ClickHouse: {e}')
            sys.exit(1)

    def create_tables(self):
        """Create necessary tables if they don't exist"""
        # Create metrics table (raw data)
        create_metrics_table = f"""
        CREATE TABLE IF NOT EXISTS {CLICKHOUSE_DB}.metrics_raw (
            timestamp DateTime,
            organization_id String,
            user_tier String,
            metric_name String,
            metric_value Float64,
            labels_json String
        )
        ENGINE = MergeTree()
        ORDER BY (timestamp, organization_id, metric_name)
        PARTITION BY toYYYYMM(timestamp)
        TTL timestamp + INTERVAL 90 DAY
        """

        # Create hourly aggregations table
        create_hourly_table = f"""
        CREATE TABLE IF NOT EXISTS {CLICKHOUSE_DB}.metrics_hourly (
            hour DateTime,
            organization_id String,
            user_tier String,
            metric_name String,
            count UInt64,
            sum Float64,
            min Float64,
            max Float64,
            avg Float64,
            p50 Float64,
            p95 Float64,
            p99 Float64
        )
        ENGINE = MergeTree()
        ORDER BY (hour, organization_id, metric_name)
        PARTITION BY toYYYYMM(hour)
        TTL hour + INTERVAL 1 YEAR
        """

        # Create cost tracking table
        create_cost_table = f"""
        CREATE TABLE IF NOT EXISTS {CLICKHOUSE_DB}.cost_tracking (
            timestamp DateTime,
            organization_id String,
            user_tier String,
            api_calls_total UInt64,
            api_calls_cost Float64,
            storage_gb Float64,
            storage_cost Float64,
            base_cost Float64,
            total_cost Float64
        )
        ENGINE = MergeTree()
        ORDER BY (timestamp, organization_id)
        PARTITION BY toYYYYMM(timestamp)
        TTL timestamp + INTERVAL 1 YEAR
        """

        try:
            self.client.execute(create_metrics_table)
            self.client.execute(create_hourly_table)
            self.client.execute(create_cost_table)
            logger.info('ClickHouse tables created/verified')
        except Exception as e:
            logger.error(f'Failed to create tables: {e}')

    def insert_raw_metrics(self, metrics: List[Dict[str, Any]]):
        """Insert raw metrics into ClickHouse"""
        if not metrics:
            return

        try:
            self.client.execute(
                f'INSERT INTO {CLICKHOUSE_DB}.metrics_raw VALUES',
                [
                    (
                        metric['timestamp'],
                        metric['organization_id'],
                        metric['user_tier'],
                        metric['metric_name'],
                        metric['metric_value'],
                        metric['labels_json'],
                    )
                    for metric in metrics
                ]
            )
            logger.info(f'Inserted {len(metrics)} raw metrics')
        except Exception as e:
            logger.error(f'Failed to insert metrics: {e}')

    def aggregate_hourly_metrics(self):
        """Generate hourly aggregations from raw metrics"""
        try:
            # Aggregate metrics from the past hour
            query = f"""
            INSERT INTO {CLICKHOUSE_DB}.metrics_hourly
            SELECT
                toStartOfHour(timestamp) as hour,
                organization_id,
                user_tier,
                metric_name,
                count(*) as count,
                sum(metric_value) as sum,
                min(metric_value) as min,
                max(metric_value) as max,
                avg(metric_value) as avg,
                quantile(0.50)(metric_value) as p50,
                quantile(0.95)(metric_value) as p95,
                quantile(0.99)(metric_value) as p99
            FROM {CLICKHOUSE_DB}.metrics_raw
            WHERE timestamp >= now() - INTERVAL 1 HOUR
                AND timestamp < toStartOfHour(now())
            GROUP BY toStartOfHour(timestamp), organization_id, user_tier, metric_name
            """
            self.client.execute(query)
            logger.info('Hourly aggregation completed')
        except Exception as e:
            logger.error(f'Failed to aggregate hourly metrics: {e}')

    def calculate_costs(self):
        """Calculate costs per organization based on usage"""
        try:
            # Get API call counts from metrics
            query = f"""
            SELECT
                timestamp,
                organization_id,
                user_tier,
                count(*) as api_calls
            FROM {CLICKHOUSE_DB}.metrics_raw
            WHERE timestamp >= now() - INTERVAL 1 HOUR
            GROUP BY timestamp, organization_id, user_tier
            """

            results = self.client.execute(query)

            cost_records = []
            for timestamp, org_id, tier, api_calls in results:
                config = COST_CONFIG.get(tier, COST_CONFIG['free'])

                api_calls_cost = (api_calls / 10) * config['per_api_call']
                base_cost = config['base'] / 30 / 24  # distribute monthly cost hourly
                total_cost = api_calls_cost + base_cost

                cost_records.append({
                    'timestamp': timestamp,
                    'organization_id': org_id,
                    'user_tier': tier,
                    'api_calls_total': api_calls,
                    'api_calls_cost': api_calls_cost,
                    'storage_gb': 0,  # Would query actual storage
                    'storage_cost': 0,
                    'base_cost': base_cost,
                    'total_cost': total_cost,
                })

            # Insert cost records
            if cost_records:
                self.client.execute(
                    f'INSERT INTO {CLICKHOUSE_DB}.cost_tracking VALUES',
                    [
                        (
                            record['timestamp'],
                            record['organization_id'],
                            record['user_tier'],
                            record['api_calls_total'],
                            record['api_calls_cost'],
                            record['storage_gb'],
                            record['storage_cost'],
                            record['base_cost'],
                            record['total_cost'],
                        )
                        for record in cost_records
                    ]
                )
                logger.info(f'Cost calculation completed for {len(cost_records)} records')
        except Exception as e:
            logger.error(f'Failed to calculate costs: {e}')


# ════════════════════════════════════════════════════════════════════════
# Prometheus Scraper
# ════════════════════════════════════════════════════════════════════════

class PrometheusScraperScraper:
    def __init__(self):
        self.base_url = PROMETHEUS_URL
        self.session = requests.Session()

    def query(self, promql: str) -> List[Dict[str, Any]]:
        """Execute PromQL query"""
        try:
            response = self.session.get(
                f'{self.base_url}/api/v1/query',
                params={'query': promql},
                timeout=10
            )
            response.raise_for_status()

            data = response.json()
            return data.get('data', {}).get('result', [])
        except Exception as e:
            logger.error(f'Prometheus query failed: {e}')
            return []

    def scrape_metrics(self) -> List[Dict[str, Any]]:
        """Scrape metrics from Prometheus"""
        metrics = []
        timestamp = datetime.utcnow()

        # Query API request metrics
        api_requests = self.query('increase(api_requests_total[30s])')
        for result in api_requests:
            labels = result.get('metric', {})
            value = float(result.get('value', [0, 0])[1])

            metrics.append({
                'timestamp': timestamp,
                'organization_id': labels.get('organization_id', 'unknown'),
                'user_tier': labels.get('tier', 'free'),
                'metric_name': 'api_requests',
                'metric_value': value,
                'labels_json': json.dumps(labels),
            })

        # Query latency metrics
        latency = self.query('rate(http_request_duration_seconds_sum[30s]) / rate(http_request_duration_seconds_count[30s])')
        for result in latency:
            labels = result.get('metric', {})
            value = float(result.get('value', [0, 0])[1]) * 1000  # Convert to ms

            metrics.append({
                'timestamp': timestamp,
                'organization_id': labels.get('organization_id', 'unknown'),
                'user_tier': labels.get('tier', 'free'),
                'metric_name': 'request_latency_ms',
                'metric_value': value,
                'labels_json': json.dumps(labels),
            })

        logger.info(f'Scraped {len(metrics)} metrics from Prometheus')
        return metrics


# ════════════════════════════════════════════════════════════════════════
# Main Service Loop
# ════════════════════════════════════════════════════════════════════════

def main():
    logger.info('Starting Phase 26-B Analytics Aggregator Service')

    clickhouse = ClickHouseManager()
    prometheus = PrometheusScraperScraper()

    hourly_tick = 0

    while True:
        try:
            # Scrape and insert metrics
            metrics = prometheus.scrape_metrics()
            clickhouse.insert_raw_metrics(metrics)

            # Every hour, aggregate metrics and calculate costs
            hourly_tick += AGGREGATION_INTERVAL
            if hourly_tick >= HOURLY_AGGREGATION_INTERVAL:
                clickhouse.aggregate_hourly_metrics()
                clickhouse.calculate_costs()
                hourly_tick = 0

            # Sleep until next aggregation
            time.sleep(AGGREGATION_INTERVAL)

        except KeyboardInterrupt:
            logger.info('Shutting down analytics aggregator')
            break
        except Exception as e:
            logger.error(f'Unexpected error: {e}')
            time.sleep(5)  # Backoff on error


if __name__ == '__main__':
    main()
