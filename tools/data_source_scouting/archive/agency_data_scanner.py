#!/usr/bin/env python3
"""
Agency Website Data Scanner
Scans discovered police websites for open data portals, reports, and OIS data

This script:
1. Reads the agency_websites.csv from the URL guesser
2. Visits each website
3. Searches for links/pages related to:
   - Open data portals
   - Annual reports
   - Transparency/accountability pages
   - Use of force data
   - Crime statistics
4. Outputs findings with URLs to specific data resources
"""

import pandas as pd
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse
import time
import logging
from datetime import datetime
import re
import os
import sys

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'data_scan_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'),
        logging.StreamHandler()
    ]
)

class AgencyDataScanner:
    def __init__(self, input_csv='agency_websites.csv', output_csv='data_resources_found.csv', 
                 timeout=10, delay=1.0, min_confidence=40):
        """
        Initialize the scanner
        
        Args:
            input_csv: CSV with discovered agency websites
            output_csv: Where to save found data resources
            timeout: Seconds to wait for page load
            delay: Seconds between requests
            min_confidence: Only scan websites with this confidence or higher
        """
        self.input_csv = input_csv
        self.output_csv = output_csv
        self.timeout = timeout
        self.delay = delay
        self.min_confidence = min_confidence
        self.results = []
        
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
        
        # Keywords to search for in links and text
        self.data_keywords = {
            'open_data': [
                'open data', 'data portal', 'open portal', 'public data',
                'data.', 'opendata', 'socrata', 'arcgis', 'ckan'
            ],
            'annual_report': [
                'annual report', 'yearly report', 'transparency report',
                'accountability report', 'annual-report', 'reports/annual'
            ],
            'use_of_force': [
                'use of force', 'force report', 'officer involved shooting',
                'ois', 'deadly force', 'police shooting', 'officer shooting',
                'use-of-force', 'uof'
            ],
            'crime_stats': [
                'crime statistics', 'crime data', 'crime stats', 'ucr',
                'uniform crime', 'crime-statistics', 'statistics'
            ],
            'transparency': [
                'transparency', 'accountability', 'public information',
                'records request', 'foia', 'open records'
            ]
        }
    
    def extract_links(self, soup, base_url):
        """Extract all links from a page"""
        links = []
        for a_tag in soup.find_all('a', href=True):
            href = a_tag['href']
            # Convert relative URLs to absolute
            full_url = urljoin(base_url, href)
            link_text = a_tag.get_text(strip=True).lower()
            links.append({
                'url': full_url,
                'text': link_text,
                'title': a_tag.get('title', '').lower()
            })
        return links
    
    def check_for_keywords(self, links, page_text):
        """Check links and page text for data-related keywords"""
        findings = {}
        
        for category, keywords in self.data_keywords.items():
            findings[category] = {
                'found': False,
                'urls': [],
                'matches': []
            }
            
            # Check links
            for link in links:
                link_str = f"{link['text']} {link['title']} {link['url']}".lower()
                for keyword in keywords:
                    if keyword in link_str:
                        findings[category]['found'] = True
                        findings[category]['urls'].append(link['url'])
                        findings[category]['matches'].append(keyword)
                        break  # Only count each link once per category
            
            # Check page text (for context)
            for keyword in keywords:
                if keyword in page_text.lower():
                    findings[category]['found'] = True
                    if keyword not in findings[category]['matches']:
                        findings[category]['matches'].append(keyword)
        
        return findings
    
    def scan_website(self, row):
        """Scan a single website for data resources"""
        agency_slug = row['slug']
        url = row['found_url']
        confidence = row['confidence_score']
        
        logging.info(f"\n{'='*60}")
        logging.info(f"Scanning: {agency_slug}")
        logging.info(f"URL: {url} (confidence: {confidence})")
        
        result = {
            'agency_slug': agency_slug,
            'ori_code': row['ori_code'],
            'city': row['city'],
            'state': row['state'],
            'website_url': url,
            'website_confidence': confidence,
            'scan_timestamp': datetime.now().isoformat(),
            'scan_success': False
        }
        
        # Initialize finding columns
        for category in self.data_keywords.keys():
            result[f'{category}_found'] = False
            result[f'{category}_urls'] = ''
            result[f'{category}_keywords'] = ''
        
        try:
            # Fetch the page
            response = requests.get(url, headers=self.headers, timeout=self.timeout, 
                                   allow_redirects=True)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Get page text for keyword matching
            page_text = soup.get_text()
            
            # Extract all links
            links = self.extract_links(soup, url)
            logging.info(f"Found {len(links)} links on page")
            
            # Check for keywords
            findings = self.check_for_keywords(links, page_text)
            
            # Update result with findings
            result['scan_success'] = True
            
            for category, data in findings.items():
                if data['found']:
                    result[f'{category}_found'] = True
                    # Deduplicate URLs and take top 3
                    unique_urls = list(dict.fromkeys(data['urls']))[:3]
                    result[f'{category}_urls'] = ' | '.join(unique_urls)
                    result[f'{category}_keywords'] = ', '.join(set(data['matches']))
                    
                    logging.info(f"✓ Found {category}: {len(unique_urls)} links")
            
            # Summary of what was found
            found_categories = [cat for cat in self.data_keywords.keys() 
                              if result[f'{cat}_found']]
            if found_categories:
                logging.info(f"Categories found: {', '.join(found_categories)}")
            else:
                logging.info("No data resources found")
                
        except requests.exceptions.Timeout:
            logging.warning(f"Timeout loading {url}")
            result['scan_error'] = 'Timeout'
        except requests.exceptions.RequestException as e:
            logging.warning(f"Error loading {url}: {str(e)}")
            result['scan_error'] = str(e)
        except Exception as e:
            logging.error(f"Unexpected error scanning {url}: {str(e)}")
            result['scan_error'] = f"Unexpected: {str(e)}"
        
        return result
    
    def process_all_websites(self, limit=None, start_from=0):
        """Process all websites from the CSV"""
        
        # Read the input CSV
        if not os.path.exists(self.input_csv):
            print(f"\nERROR: Cannot find {self.input_csv}")
            print("Make sure you've run the URL guesser first!")
            sys.exit(1)
        
        df = pd.read_csv(self.input_csv)
        logging.info(f"Loaded {len(df)} agencies from {self.input_csv}")
        
        # Filter to only agencies with found URLs and sufficient confidence
        df = df[df['found_url'].notna()]
        df = df[df['confidence_score'] >= self.min_confidence]
        logging.info(f"Filtered to {len(df)} agencies with URLs (confidence ≥ {self.min_confidence})")
        
        if len(df) == 0:
            print("\nNo websites to scan! Check your confidence threshold.")
            return
        
        # Apply limits
        if start_from > 0:
            df = df.iloc[start_from:]
            logging.info(f"Starting from row {start_from}")
        
        if limit:
            df = df.head(limit)
            logging.info(f"Limited to {limit} agencies")
        
        total = len(df)
        
        # Process each website
        for idx, row in df.iterrows():
            result = self.scan_website(row)
            self.results.append(result)
            
            # Progress
            progress = len(self.results)
            print(f"Progress: {progress}/{total} ({progress/total*100:.1f}%)", end='\r')
            
            # Save periodically
            if len(self.results) % 20 == 0:
                self.save_results()
            
            # Respectful delay
            time.sleep(self.delay)
        
        # Final save
        self.save_results()
        logging.info(f"\nCompleted! Scanned {len(self.results)} websites")
        self.print_summary()
    
    def save_results(self):
        """Save results to CSV"""
        if self.results:
            df = pd.DataFrame(self.results)
            df.to_csv(self.output_csv, index=False)
    
    def print_summary(self):
        """Print summary statistics"""
        if not self.results:
            return
        
        df = pd.DataFrame(self.results)
        
        scanned = df['scan_success'].sum()
        
        print("\n" + "="*60)
        print("SCAN SUMMARY")
        print("="*60)
        print(f"Total websites scanned: {len(self.results)}")
        print(f"Successful scans: {scanned}")
        print(f"Failed scans: {len(self.results) - scanned}")
        
        print("\nData resources found:")
        for category in self.data_keywords.keys():
            found = df[f'{category}_found'].sum()
            pct = (found / len(self.results) * 100) if len(self.results) > 0 else 0
            print(f"  {category.replace('_', ' ').title()}: {found} ({pct:.1f}%)")
        
        # Agencies with any data found
        any_data = df[[f'{cat}_found' for cat in self.data_keywords.keys()]].any(axis=1).sum()
        print(f"\nAgencies with ANY data resources: {any_data} ({any_data/len(self.results)*100:.1f}%)")
        
        print("="*60)
        print(f"\nDetailed results saved to: {self.output_csv}")
        print("="*60)


def main():
    """Main function"""
    
    print("\n" + "="*60)
    print("AGENCY WEBSITE DATA SCANNER")
    print("="*60)
    
    # Check for input file
    if not os.path.exists('agency_websites.csv'):
        print("\nERROR: Cannot find agency_websites.csv")
        print("Run agency_url_guesser.py first to find websites!")
        sys.exit(1)
    
    print("\nThis script scans discovered websites for:")
    print("  • Open data portals")
    print("  • Annual reports")
    print("  • Use of force data")
    print("  • Crime statistics")
    print("  • Transparency/accountability pages")
    print("="*60 + "\n")
    
    scanner = AgencyDataScanner(
        min_confidence=40  # Only scan medium+ confidence sites
    )
    
    # For testing, scan first 20 high-confidence sites
    print("Starting TEST RUN with first 20 websites...")
    print("(Edit script to change limit=20 to limit=None for full scan)\n")
    
    scanner.process_all_websites()
    
    print("\nDone! Check data_resources_found.csv for results.")


if __name__ == "__main__":
    main()
