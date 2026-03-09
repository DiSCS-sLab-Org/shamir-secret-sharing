#!/usr/bin/env python3
# fetch_all_cowrie_attackers.py - Fetch top Cowrie attacker IPs

from elasticsearch import Elasticsearch
import argparse
import os
from datetime import datetime, timedelta

# Project root directory (parent of fetch_scripts/)
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Configuration - same as fetch_cowrie_data.py
ES_CONFIG = {
    "host": "https://139.91.70.222:9200",
    "api_key": "cnVJcW9wc0JCNlJtNjdPSUlXTG86RnlKYzl6b0RBQTV5VmtjTE5VVEtCdw==",
    "verify_certs": False,
    "headers": {"Accept": "application/vnd.elasticsearch+json; compatible-with=8"}
}

QUERY_CONFIG = {
    "index": "logstash-*",
    "type": "Cowrie",
    "exclude_regex": "139\\.91\\..*",  # Exclude internal IPs
    "honeypot_subnet_regex": "139\\.91\\.130\\..*",  # Only attacks on honeypot subnet
    "limit": 100  # Top N attacker IPs to return
}


def get_top_attacking_ips(time_back="24h", honeypot_regex=None, protocol=None):
    """Get the top attacking IP addresses by attack count"""

    client = Elasticsearch(
        ES_CONFIG["host"],
        api_key=ES_CONFIG["api_key"],
        verify_certs=ES_CONFIG["verify_certs"],
        headers=ES_CONFIG["headers"]
    )

    scope_parts = []
    if honeypot_regex:
        scope_parts.append(f"dest_ip matching {honeypot_regex}")
    if protocol:
        scope_parts.append(f"protocol={protocol}")

    if scope_parts:
        print(
            f"Querying top {QUERY_CONFIG['limit']} attacking IPs for last {time_back} "
            f"with {' and '.join(scope_parts)}..."
        )
    else:
        print(f"Querying top {QUERY_CONFIG['limit']} attacking IPs for last {time_back}...")

    agg_config = {
        "terms": {
            "field": "src_ip",
            "size": QUERY_CONFIG["limit"],
            "order": {"_count": "desc"},
        },
        "aggs": {
            "attack_count": {"value_count": {"field": "src_ip"}}
        }
    }

    must_filters = [
        {"match": {"type": QUERY_CONFIG["type"]}},
    ]
    if protocol:
        must_filters.append({"match": {"protocol": protocol}})
    if honeypot_regex:
        must_filters.append({"regexp": {"dest_ip": honeypot_regex}})

    query = {
        "size": 0,
        "query": {
            "bool": {
                "must": must_filters,
                "filter": [
                    {"range": {"@timestamp": {"gte": f"now-{time_back}", "lt": "now"}}},
                ],
                "must_not": [
                    {"regexp": {"src_ip": QUERY_CONFIG["exclude_regex"]}},
                ],
            }
        },
        "aggs": {
            "attacking_ips": agg_config
        },
    }

    try:
        response = client.search(index=QUERY_CONFIG["index"], body=query)
        buckets = response['aggregations']['attacking_ips']['buckets']
    except Exception as e:
        print(f"Error querying Elasticsearch: {e}")
        return []

    ip_attack_list = [(bucket['key'], bucket['doc_count']) for bucket in buckets]

    print(f"Retrieved {len(ip_attack_list)} attacking IP addresses")
    return ip_attack_list


def save_ips_only(data, filename):
    """Save only IP addresses (one per line, no headers)"""
    try:
        with open(filename, 'w') as f:
            for ip_address, _ in data:
                f.write(f"{ip_address}\n")

        print(f"IP list saved to: {filename}")
        return True

    except Exception as e:
        print(f"Error saving to file: {e}")
        return False


def test_connection():
    """Test Elasticsearch connection"""
    try:
        client = Elasticsearch(
            ES_CONFIG["host"],
            api_key=ES_CONFIG["api_key"],
            verify_certs=ES_CONFIG["verify_certs"],
            headers=ES_CONFIG["headers"]
        )

        info = client.info()
        print(f"Connected to Elasticsearch: {info['version']['number']}")
        return True
    except Exception as e:
        print(f"Connection failed: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Fetch the top Cowrie attacker IPs from Elasticsearch",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Get the top attacking IPs from last 24 hours (all protocols, saves to data/)
  python3 fetch_all_cowrie_attackers.py --time 24h

  # Get only SSH attacking IPs
  python3 fetch_all_cowrie_attackers.py --time 24h --protocol ssh

  # Get the top attacking IPs from last week with custom output dir
  python3 fetch_all_cowrie_attackers.py --time 7d --output-dir output --output attackers_7d.txt

  # Test connection
  python3 fetch_all_cowrie_attackers.py --test
        """
    )

    parser.add_argument(
        "--time",
        default="24h",
        help="Time range (e.g., 1h, 6h, 24h, 2d, 7d) (default: 24h)"
    )
    parser.add_argument(
        "--honeypot-subnet",
        default=QUERY_CONFIG["honeypot_subnet_regex"],
        help="Optional dest_ip regex filter (default: honeypot subnet)"
    )
    parser.add_argument(
        "--protocol",
        default="all",
        help="Protocol filter (default: all). Example: ssh, telnet, all"
    )

    parser.add_argument(
        "--output",
        help="Output filename (default: auto-generated)"
    )

    parser.add_argument(
        "--output-dir",
        default=os.path.join(ROOT_DIR, "data", "fetch_all"),
        help="Output directory (default: data/fetch_all)"
    )

    parser.add_argument(
        "--test",
        action="store_true",
        help="Test connection and exit"
    )

    args = parser.parse_args()

    print("Cowrie Top Attackers Fetcher")
    print("=" * 28)

    if args.test:
        test_connection()
        return

    protocol_filter = (args.protocol or "").strip().lower()
    if protocol_filter in ("", "all", "*", "any"):
        protocol_filter = None

    data = get_top_attacking_ips(args.time, args.honeypot_subnet, protocol_filter)

    if not data:
        print("No data retrieved. Check your API key and connection.")
        return

    # Create output directory if needed
    os.makedirs(args.output_dir, exist_ok=True)

    # Calculate the actual UTC time range used
    from datetime import timezone
    end_utc = datetime.now(timezone.utc)
    # Parse time_back to calculate start time
    time_val = args.time
    if time_val.endswith('h'):
        hours = int(time_val[:-1])
        start_utc = end_utc - timedelta(hours=hours)
    elif time_val.endswith('d'):
        days = int(time_val[:-1])
        start_utc = end_utc - timedelta(days=days)
    else:
        start_utc = end_utc - timedelta(hours=24)  # default

    # Generate filename if not provided
    if not args.output:
        day_stamp = datetime.now().strftime("%Y%m%d_%H%M")
        args.output = f"cowrie_attackers_{day_stamp}_{args.time}.txt"

    # Build full output path
    output_path = os.path.join(args.output_dir, args.output)

    # Save data
    save_ips_only(data, output_path)

    # Show statistics
    total_attacks = sum(count for _, count in data)
    print(f"\nStatistics:")
    print(f"  Total unique IPs: {len(data)}")
    print(f"  Total attacks: {total_attacks}")
    if data:
        print(f"  Max attacks from single IP: {max(count for _, count in data)}")
        print(f"  Top 5 attackers:")
        for i, (ip, count) in enumerate(data[:5]):
            print(f"    {i+1}. {ip}: {count} attacks")


if __name__ == "__main__":
    main()
