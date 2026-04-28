#!/usr/bin/env python3
"""
Performance test results analyzer
Generates comparison reports and identifies regressions

Usage:
  python3 scripts/perf/analyze-performance.py results-medium-20260428-120000.csv
  python3 scripts/perf/analyze-performance.py results-heavy.csv baseline-heavy.json
  python3 scripts/perf/analyze-performance.py --scenario=medium --compare=baseline
"""

import json
import csv
import sys
import argparse
from pathlib import Path
from datetime import datetime
import statistics
from typing import Dict, List, Optional

def load_locust_results(csv_file: Path) -> Dict:
    """Parse Locust CSV results"""
    results = {}
    
    if not csv_file.exists():
        print(f"Error: Results file not found: {csv_file}")
        return results
    
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            print("Error: CSV file is empty or malformed")
            return results
        
        for row in reader:
            endpoint = row.get('Name', 'Unknown')
            
            try:
                results[endpoint] = {
                    'requests': int(row.get('# requests', 0)),
                    'failures': int(row.get('# failures', 0)),
                    'avg_response': float(row.get('Average Response Time', 0)),
                    'min_response': float(row.get('Min Response Time', 0)),
                    'max_response': float(row.get('Max Response Time', 0)),
                    'median_response': float(row.get('Median Response Time', 0)),
                    'p95': float(row.get('95%', 0)),
                    'p99': float(row.get('99%', 0)),
                    'requests_per_sec': float(row.get('Requests/s', 0)),
                }
            except (ValueError, TypeError) as e:
                print(f"Warning: Could not parse row for {endpoint}: {e}")
                continue
    
    return results

def load_baseline(baseline_file: Optional[Path]) -> Dict:
    """Load baseline metrics from JSON"""
    if not baseline_file or not baseline_file.exists():
        return {}
    
    with open(baseline_file, 'r') as f:
        data = json.load(f)
        return data.get('details', {})

def calculate_regression(current: Dict, baseline: Dict) -> Dict:
    """Calculate performance regression from baseline"""
    if not baseline:
        return {'status': 'baseline', 'change_percent': 0}
    
    baseline_avg = baseline.get('current', {}).get('avg_response', 0)
    current_avg = current.get('avg_response', 0)
    
    if baseline_avg == 0:
        return {'status': 'unknown', 'change_percent': 0}
    
    change_percent = ((current_avg - baseline_avg) / baseline_avg) * 100
    
    if change_percent > 10:
        status = 'regression'
    elif change_percent < -10:
        status = 'improvement'
    else:
        status = 'stable'
    
    return {
        'status': status,
        'change_percent': round(change_percent, 2),
        'baseline_ms': baseline_avg,
        'current_ms': current_avg
    }

def check_success_criteria(results: Dict, scenario: str = 'medium') -> Dict:
    """Check if results meet success criteria"""
    
    criteria_map = {
        'light': {'p95_target': 300, 'error_target': 0.05},
        'medium': {'p95_target': 500, 'error_target': 0.1},
        'heavy': {'p95_target': 700, 'error_target': 0.15},
        'spike': {'p95_target': 1000, 'error_target': 0.3},
        'sustained': {'p95_target': 600, 'error_target': 0.1},
    }
    
    criteria = criteria_map.get(scenario, criteria_map['medium'])
    
    # Calculate aggregate metrics
    total_requests = sum(r['requests'] for r in results.values())
    total_failures = sum(r['failures'] for r in results.values())
    error_rate = (total_failures / total_requests * 100) if total_requests > 0 else 0
    
    p95_times = [r['p95'] for r in results.values() if r['p95'] > 0]
    max_p95 = max(p95_times) if p95_times else 0
    
    return {
        'p95_pass': max_p95 <= criteria['p95_target'],
        'p95_target': criteria['p95_target'],
        'p95_actual': max_p95,
        'error_pass': error_rate <= criteria['error_target'],
        'error_target': criteria['error_target'],
        'error_actual': error_rate,
        'all_pass': (max_p95 <= criteria['p95_target']) and (error_rate <= criteria['error_target']),
    }

def generate_report(
    results: Dict,
    baseline: Dict,
    scenario: str,
    csv_file: Path
) -> Dict:
    """Generate comprehensive performance report"""
    
    # Calculate aggregate metrics
    total_requests = sum(r['requests'] for r in results.values())
    total_failures = sum(r['failures'] for r in results.values())
    error_rate = (total_failures / total_requests * 100) if total_requests > 0 else 0
    
    response_times = [r['avg_response'] for r in results.values() if r['requests'] > 0]
    avg_response = statistics.mean(response_times) if response_times else 0
    
    p95_times = [r['p95'] for r in results.values() if r['p95'] > 0]
    max_p95 = max(p95_times) if p95_times else 0
    
    throughput = sum(r['requests_per_sec'] for r in results.values() if r['requests_per_sec'] > 0)
    
    report = {
        'metadata': {
            'timestamp': datetime.now().isoformat(),
            'scenario': scenario,
            'results_file': str(csv_file.name),
            'duration_seconds': None,  # Would be extracted from Locust stats if available
        },
        'summary': {
            'total_requests': total_requests,
            'total_failures': total_failures,
            'error_rate_percent': round(error_rate, 3),
            'avg_response_time_ms': round(avg_response, 1),
            'max_p95_response_time_ms': round(max_p95, 1),
            'throughput_req_sec': round(throughput, 1),
        },
        'success_criteria': check_success_criteria(results, scenario),
        'endpoints': {},
    }
    
    # Per-endpoint details
    for endpoint, metrics in sorted(results.items()):
        if metrics['requests'] > 0:
            error_pct = (metrics['failures'] / metrics['requests'] * 100) if metrics['requests'] > 0 else 0
            
            baseline_metrics = baseline.get(endpoint, {})
            regression = calculate_regression(metrics, baseline_metrics)
            
            report['endpoints'][endpoint] = {
                'current': {
                    'requests': metrics['requests'],
                    'failures': metrics['failures'],
                    'error_rate_percent': round(error_pct, 3),
                    'avg_response_ms': round(metrics['avg_response'], 1),
                    'p95_response_ms': round(metrics['p95'], 1),
                    'p99_response_ms': round(metrics['p99'], 1),
                    'min_response_ms': round(metrics['min_response'], 1),
                    'max_response_ms': round(metrics['max_response'], 1),
                },
                'regression': regression if baseline_metrics else {'status': 'no_baseline'},
            }
    
    return report

def print_report(report: Dict) -> None:
    """Pretty print performance report"""
    print("\n" + "=" * 70)
    print("PERFORMANCE TEST REPORT")
    print("=" * 70)
    
    meta = report['metadata']
    print(f"\nTest Scenario: {meta['scenario'].upper()}")
    print(f"Timestamp: {meta['timestamp']}")
    
    print("\n" + "-" * 70)
    print("SUMMARY METRICS")
    print("-" * 70)
    
    summary = report['summary']
    print(f"Total Requests: {summary['total_requests']:,}")
    print(f"Total Failures: {summary['total_failures']:,}")
    print(f"Error Rate: {summary['error_rate_percent']:.3f}%")
    print(f"Average Response Time: {summary['avg_response_time_ms']:.1f}ms")
    print(f"Max P95 Response Time: {summary['max_p95_response_time_ms']:.1f}ms")
    print(f"Throughput: {summary['throughput_req_sec']:.1f} req/sec")
    
    criteria = report['success_criteria']
    print("\n" + "-" * 70)
    print("SUCCESS CRITERIA")
    print("-" * 70)
    print(f"P95 Response Time: {'✅ PASS' if criteria['p95_pass'] else '❌ FAIL'} "
          f"({criteria['p95_actual']:.0f}ms / {criteria['p95_target']}ms target)")
    print(f"Error Rate: {'✅ PASS' if criteria['error_pass'] else '❌ FAIL'} "
          f"({criteria['error_actual']:.3f}% / {criteria['error_target']}% target)")
    print(f"Overall: {'✅ PASS' if criteria['all_pass'] else '❌ FAIL'}")
    
    print("\n" + "-" * 70)
    print("ENDPOINT DETAILS")
    print("-" * 70)
    
    for endpoint, data in sorted(report['endpoints'].items()):
        current = data['current']
        print(f"\n{endpoint}")
        print(f"  Requests: {current['requests']:,} | Failures: {current['failures']}")
        print(f"  Error Rate: {current['error_rate_percent']:.3f}%")
        print(f"  Response Time: {current['avg_response_ms']:.0f}ms avg | "
              f"P95: {current['p95_response_ms']:.0f}ms | P99: {current['p99_response_ms']:.0f}ms")
        print(f"  Range: {current['min_response_ms']:.0f}ms - {current['max_response_ms']:.0f}ms")
        
        if data['regression']['status'] != 'no_baseline':
            regression = data['regression']
            status_icon = '📈' if regression['status'] == 'regression' else \
                         '📉' if regression['status'] == 'improvement' else '➡️'
            print(f"  Regression vs Baseline: {status_icon} {regression['change_percent']:+.1f}%")
    
    print("\n" + "=" * 70)

def main():
    parser = argparse.ArgumentParser(
        description='Analyze performance test results'
    )
    parser.add_argument('results_file', help='Path to Locust CSV results file')
    parser.add_argument(
        '--baseline',
        help='Path to baseline JSON file for regression detection'
    )
    parser.add_argument(
        '--scenario',
        default='medium',
        choices=['light', 'medium', 'heavy', 'spike', 'sustained'],
        help='Test scenario for success criteria comparison'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output report as JSON'
    )
    parser.add_argument(
        '--save',
        help='Save report to file'
    )
    
    args = parser.parse_args()
    
    results_file = Path(args.results_file)
    baseline_file = Path(args.baseline) if args.baseline else None
    
    # Load data
    results = load_locust_results(results_file)
    if not results:
        print("Error: No results to analyze")
        sys.exit(1)
    
    baseline = load_baseline(baseline_file)
    
    # Generate report
    report = generate_report(results, baseline, args.scenario, results_file)
    
    # Output
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_report(report)
    
    # Save if requested
    if args.save:
        save_path = Path(args.save)
        with open(save_path, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"\nReport saved to: {save_path}")
    
    # Exit with appropriate code
    if not report['success_criteria']['all_pass']:
        sys.exit(1)

if __name__ == '__main__':
    main()
