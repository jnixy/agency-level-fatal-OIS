#!/usr/bin/env python3
"""
Data Scanner Results Analyzer
Helps prioritize and filter the results from the data scanner

This script:
1. Reads data_resources_found.csv
2. Ranks agencies by data resource quality
3. Creates filtered lists for manual review
4. Exports high-priority targets
"""

import pandas as pd
import os
import sys

def analyze_results(input_csv='data_resources_found.csv'):
    """Analyze and prioritize scanner results"""
    
    if not os.path.exists(input_csv):
        print(f"ERROR: Cannot find {input_csv}")
        sys.exit(1)
    
    df = pd.read_csv(input_csv)
    print(f"\nLoaded {len(df)} scanned agencies\n")
    
    # Calculate priority scores
    df['priority_score'] = 0
    
    # High value: Use of force data (10 points)
    df.loc[df['use_of_force_found'] == True, 'priority_score'] += 10
    
    # Medium-high value: Open data portals (5 points)
    df.loc[df['open_data_found'] == True, 'priority_score'] += 5
    
    # Medium value: Annual reports (3 points)
    df.loc[df['annual_report_found'] == True, 'priority_score'] += 3
    
    # Low-medium value: Crime stats (2 points)
    df.loc[df['crime_stats_found'] == True, 'priority_score'] += 2
    
    # Low value: Transparency pages (1 point)
    df.loc[df['transparency_found'] == True, 'priority_score'] += 1
    
    # Sort by priority
    df = df.sort_values('priority_score', ascending=False)
    
    # Create output directory
    os.makedirs('scanner_analysis', exist_ok=True)
    
    # 1. HIGH PRIORITY: Agencies with use of force data
    high_priority = df[df['use_of_force_found'] == True].copy()
    if len(high_priority) > 0:
        high_priority.to_csv('scanner_analysis/01_HIGH_PRIORITY_use_of_force.csv', index=False)
        print("="*60)
        print(f"HIGH PRIORITY: {len(high_priority)} agencies with use of force mentions")
        print("="*60)
        for _, row in high_priority.iterrows():
            print(f"\n{row['city']}, {row['state']}")
            print(f"  Website: {row['website_url']}")
            if pd.notna(row['use_of_force_urls']):
                urls = row['use_of_force_urls'].split(' | ')
                for url in urls[:2]:  # Show first 2 URLs
                    print(f"  → {url}")
    else:
        print("No agencies found with explicit use of force data")
    
    # 2. MEDIUM-HIGH PRIORITY: Agencies with open data portals
    open_data = df[df['open_data_found'] == True].copy()
    if len(open_data) > 0:
        open_data.to_csv('scanner_analysis/02_MEDIUM_HIGH_open_data_portals.csv', index=False)
        print(f"\nMEDIUM-HIGH PRIORITY: {len(open_data)} agencies with open data portals")
        print("These may contain use of force data even if not explicitly mentioned")
    
    # 3. MEDIUM PRIORITY: Agencies with annual reports
    annual = df[df['annual_report_found'] == True].copy()
    if len(annual) > 0:
        annual.to_csv('scanner_analysis/03_MEDIUM_annual_reports.csv', index=False)
        print(f"\nMEDIUM PRIORITY: {len(annual)} agencies with annual reports")
        print("Annual reports sometimes include OIS statistics")
    
    # 4. Worth checking: Multiple data sources
    multiple = df[df['priority_score'] >= 5].copy()
    multiple.to_csv('scanner_analysis/04_multiple_data_sources.csv', index=False)
    print(f"\n{len(multiple)} agencies with multiple data resources (score >=5)")
    
    # 5. All results ranked
    df.to_csv('scanner_analysis/05_all_results_ranked.csv', index=False)
    print(f"\nFull ranked results: {len(df)} agencies")
    
    # Statistics
    print("\n" + "="*60)
    print("SUMMARY STATISTICS")
    print("="*60)
    print(f"Total agencies scanned: {len(df)}")
    print(f"Agencies with any data: {len(df[df['priority_score'] > 0])}")
    print(f"\nBy resource type:")
    print(f"  Use of force: {len(df[df['use_of_force_found'] == True])}")
    print(f"  Open data: {len(df[df['open_data_found'] == True])}")
    print(f"  Annual reports: {len(df[df['annual_report_found'] == True])}")
    print(f"  Crime stats: {len(df[df['crime_stats_found'] == True])}")
    print(f"  Transparency: {len(df[df['transparency_found'] == True])}")
    
    # Top 10 agencies by priority
    print("\n" + "="*60)
    print("TOP 10 AGENCIES TO CHECK FIRST")
    print("="*60)
    top10 = df.head(10)
    for idx, row in top10.iterrows():
        print(f"\n{row['city']}, {row['state']} (Score: {row['priority_score']})")
        resources = []
        if row['use_of_force_found']:
            resources.append("Use of Force")
        if row['open_data_found']:
            resources.append("Open Data")
        if row['annual_report_found']:
            resources.append("Annual Reports")
        if row['crime_stats_found']:
            resources.append("Crime Stats")
        print(f"  Resources: {', '.join(resources)}")
        print(f"  URL: {row['website_url']}")
    
    print("\n" + "="*60)
    print("FILES CREATED")
    print("="*60)
    print("All files saved to scanner_analysis/ folder:")
    print("  01_HIGH_PRIORITY_use_of_force.csv")
    print("  02_MEDIUM_HIGH_open_data_portals.csv")
    print("  03_MEDIUM_annual_reports.csv")
    print("  04_multiple_data_sources.csv")
    print("  05_all_results_ranked.csv")
    print("="*60)


if __name__ == "__main__":
    print("\n" + "="*60)
    print("DATA SCANNER RESULTS ANALYZER")
    print("="*60)
    analyze_results()
    print("\nAnalysis complete!\n")
