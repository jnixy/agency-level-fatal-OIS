#!/usr/bin/env python3
"""
Agency URL Guesser
Constructs likely police department URLs and tests if they exist

Instead of searching, this script intelligently guesses common URL patterns
and tests which ones are valid. Much faster and avoids rate limiting.
"""

import pandas as pd
import requests
from urllib.parse import urlparse
import time
import logging
from datetime import datetime
import os
import sys

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'agency_url_check_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'),
        logging.StreamHandler()
    ]
)

class AgencyURLGuesser:
    def __init__(self, input_csv='../../data/agency_key.csv', output_csv='agency_websites.csv', timeout=5):
        self.input_csv = input_csv
        self.output_csv = output_csv
        self.timeout = timeout
        self.results = []
        
        # User agent
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
    
    def parse_agency_name(self, agency_slug):
        """Parse agency slug into components"""
        parts = agency_slug.split('_')
        state = parts[-1].upper() if len(parts[-1]) == 2 else None
        
        if state:
            name_parts = parts[:-1]
        else:
            name_parts = parts
        
        city_name = ' '.join(word.capitalize() for word in name_parts)
        city_slug = '-'.join(name_parts)  # For URLs
        city_no_spaces = ''.join(name_parts)  # For URLs without dashes
        
        is_county = 'county' in agency_slug.lower()
        is_sheriff = 'sheriff' in agency_slug.lower() or is_county
        
        return {
            'city_name': city_name,
            'city_slug': city_slug,
            'city_no_spaces': city_no_spaces,
            'state': state,
            'state_lower': state.lower() if state else '',
            'is_county': is_county,
            'is_sheriff': is_sheriff
        }
    
    def generate_url_patterns(self, info):
        """Generate likely URL patterns for an agency"""
        city = info['city_slug']
        city_no_dash = info['city_no_spaces']
        state = info['state_lower']
        
        urls = []
        
        # Pattern 1: city-state.gov patterns (most common)
        if state:
            urls.extend([
                f"https://{city}.{state}.gov",
                f"https://www.{city}.{state}.gov",
                f"https://{city}{state}.gov",
                f"https://www.{city}{state}.gov",
            ])
        
        # Pattern 2: cityof patterns
        urls.extend([
            f"https://www.cityof{city_no_dash}.org",
            f"https://www.cityof{city_no_dash}.com",
            f"https://www.cityof{city_no_dash}.us",
            f"https://cityof{city_no_dash}.org",
        ])
        
        # Pattern 3: Police-specific domains
        if not info['is_sheriff']:
            urls.extend([
                f"https://{city}pd.gov",
                f"https://www.{city}pd.gov",
                f"https://{city}police.org",
                f"https://www.{city}police.org",
                f"https://{city}-police.org",
            ])
        
        # Pattern 4: County patterns (for counties)
        if info['is_county']:
            county_name = info['city_slug'].replace('-county', '')
            urls.extend([
                f"https://{county_name}county.{state}.gov" if state else None,
                f"https://www.{county_name}county{state}.gov" if state else None,
                f"https://{county_name}countysheriff.org",
                f"https://www.{county_name}sheriff.org",
                f"https://{county_name}so.org",
            ])
        
        # Pattern 5: State-level agencies
        if 'state' in info['city_slug'] or 'highway' in info['city_slug']:
            urls.extend([
                f"https://dps.{state}.gov" if state else None,
                f"https://www.dps.{state}.gov" if state else None,
                f"https://statepatrol.{state}.gov" if state else None,
            ])
        
        # Remove None values and duplicates
        urls = list(dict.fromkeys([u for u in urls if u]))
        
        return urls
    
    def test_url(self, url):
        """Test if a URL exists and is valid"""
        try:
            response = requests.head(url, headers=self.headers, timeout=self.timeout, 
                                    allow_redirects=True)
            
            # Consider both 200 and 3xx redirects as success
            if response.status_code < 400:
                # Try to get the final URL after redirects
                final_url = response.url
                
                # Quick check: does it look like a government/police site?
                domain = urlparse(final_url).netloc.lower()
                
                confidence = 30  # Base confidence for any working URL
                
                if '.gov' in domain:
                    confidence += 50
                elif '.us' in domain:
                    confidence += 30
                elif '.org' in domain:
                    confidence += 10
                
                # Check for police/sheriff keywords in domain
                if any(kw in domain for kw in ['police', 'sheriff', 'pd', 'so']):
                    confidence += 20
                
                return True, final_url, confidence, f"HTTP {response.status_code}"
            else:
                return False, None, 0, f"HTTP {response.status_code}"
                
        except requests.exceptions.Timeout:
            return False, None, 0, "Timeout"
        except requests.exceptions.ConnectionError:
            return False, None, 0, "Connection failed"
        except Exception as e:
            return False, None, 0, str(e)
    
    def find_agency_url(self, agency_slug, ori_code):
        """Find URL for a single agency"""
        logging.info(f"\n{'='*60}")
        logging.info(f"Checking: {agency_slug} (ORI: {ori_code})")
        
        info = self.parse_agency_name(agency_slug)
        logging.info(f"Parsed as: {info['city_name']} in {info['state']}")
        
        # Generate URL candidates
        candidate_urls = self.generate_url_patterns(info)
        logging.info(f"Testing {len(candidate_urls)} URL patterns...")
        
        best_url = None
        best_confidence = 0
        best_notes = ""
        
        # Test each URL
        for url in candidate_urls:
            works, final_url, confidence, notes = self.test_url(url)
            
            if works:
                logging.info(f"✓ FOUND: {final_url} (confidence: {confidence})")
                if confidence > best_confidence:
                    best_url = final_url
                    best_confidence = confidence
                    best_notes = notes
                    
                # If we found a high-confidence .gov site, we can stop
                if confidence >= 80:
                    break
            else:
                logging.debug(f"✗ Failed: {url} ({notes})")
            
            # Small delay to be respectful
            time.sleep(0.1)
        
        result = {
            'slug': agency_slug,
            'ori_code': ori_code,
            'city': info['city_name'],
            'state': info['state'],
            'found_url': best_url,
            'confidence_score': best_confidence,
            'notes': best_notes,
            'timestamp': datetime.now().isoformat()
        }
        
        logging.info(f"Result: {best_url or 'NOT FOUND'} (confidence: {best_confidence})")
        
        return result
    
    def process_all_agencies(self, limit=None, start_from=0):
        """Process all agencies"""
        df = pd.read_csv(self.input_csv)
        logging.info(f"Loaded {len(df)} agencies from {self.input_csv}")
        
        if start_from > 0:
            df = df.iloc[start_from:]
            logging.info(f"Starting from row {start_from}")
        
        if limit:
            df = df.head(limit)
            logging.info(f"Limited to {limit} agencies")
        
        total = len(df)
        
        for idx, row in df.iterrows():
            agency_slug = row['slug']
            ori_code = row['ori7']
            
            result = self.find_agency_url(agency_slug, ori_code)
            self.results.append(result)
            
            # Progress indicator
            progress = len(self.results)
            print(f"Progress: {progress}/{total} ({progress/total*100:.1f}%)", end='\r')
            
            # Save periodically
            if len(self.results) % 20 == 0:
                self.save_results()
                logging.info(f"Progress saved: {len(self.results)} agencies processed")
        
        self.save_results()
        logging.info(f"\nCompleted! Processed {len(self.results)} agencies")
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
        
        found = df['found_url'].notna().sum()
        high_conf = (df['confidence_score'] >= 70).sum()
        med_conf = ((df['confidence_score'] >= 40) & (df['confidence_score'] < 70)).sum()
        low_conf = ((df['confidence_score'] > 0) & (df['confidence_score'] < 40)).sum()
        
        print("\n" + "="*60)
        print("SUMMARY")
        print("="*60)
        print(f"Total processed: {len(self.results)}")
        print(f"URLs found: {found} ({found/len(self.results)*100:.1f}%)")
        print(f"\nBy confidence:")
        print(f"  High (≥70):     {high_conf}")
        print(f"  Medium (40-69): {med_conf}")
        print(f"  Low (1-39):     {low_conf}")
        print(f"  Not found:      {len(self.results) - found}")
        print("="*60)


def main():
    """Main function"""
    
    print("\n" + "="*60)
    print("AGENCY URL GUESSER")
    print("="*60)
    
    # Check for CSV
    if not os.path.exists('../../data/agency_key.csv'):
        print("\nERROR: Cannot find ../../data/agency_key.csv")
        print("Run this script from tools/data_source_scouting/.")
        sys.exit(1)
    
    print("\nThis script guesses common URL patterns and tests them.")
    print("Much faster than searching! (~5 seconds per agency)")
    print("="*60 + "\n")
    
    guesser = AgencyURLGuesser()
    
    # Test run with 20 agencies
    print("Starting TEST RUN with 20 agencies...")
    print("(Edit the script to change limit=20 to limit=None for full run)\n")
    
    guesser.process_all_agencies(limit=417)
    
    print("\nDone! Check agency_websites.csv for results.")


if __name__ == "__main__":
    main()
