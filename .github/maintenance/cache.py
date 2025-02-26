import requests
import sys
import os

# Your GitHub Personal Access Token
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")

# Repository details
REPO_OWNER = "SideStore"
REPO_NAME = "SideStore"


API_URL = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/actions/caches"

# Common headers for GitHub API calls
HEADERS = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {GITHUB_TOKEN}"
}

def list_caches():
    response = requests.get(API_URL, headers=HEADERS)
    if response.status_code != 200:
        print(f"Failed to list caches. HTTP {response.status_code}")
        print("Response:", response.text)
        sys.exit(1)
    data = response.json()
    return data.get("actions_caches", [])

def delete_cache(cache_id):
    delete_url = f"{API_URL}/{cache_id}"
    response = requests.delete(delete_url, headers=HEADERS)
    return response.status_code

def main():
    caches = list_caches()
    if not caches:
        print("No caches found.")
        return

    print("Found caches:")
    for cache in caches:
        print(f"ID: {cache.get('id')}, Key: {cache.get('key')}")
    
    print("\nDeleting caches...")
    for cache in caches:
        cache_id = cache.get("id")
        status = delete_cache(cache_id)
        if status == 204:
            print(f"Successfully deleted cache with ID: {cache_id}")
        else:
            print(f"Failed to delete cache with ID: {cache_id}. HTTP status code: {status}")
    
    print("All caches processed.")

if __name__ == "__main__":
    main()


### How to use
'''
just export the GITHUB_TOKEN and then run this script via `python3 cache.py' to delete the caches 
'''