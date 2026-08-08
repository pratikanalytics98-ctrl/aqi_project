.PHONY: install fetch transform run serve clean

install:
	pip install -r pipeline/requirements.txt

# Fetch once and store into data/raw/.
fetch:
	cd pipeline && python fetch.py

# Run the DuckDB pipeline against whatever is already in data/raw/.
transform:
	cd pipeline && python transform.py

# End-to-end: fetch + transform.
run: fetch transform

# Preview the dashboard locally on http://localhost:8000
serve:
	python -m http.server 8000 --directory docs

# Wipe processed data (keeps raw JSON so silver/gold can be rebuilt).
clean:
	rm -rf data/bronze/* data/silver/* data/gold/* docs/data/*.json
