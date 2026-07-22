.DEFAULT_GOAL := test

# ─── Setup ───────────────────────────────────────────────────────────────────
init:
	fvm flutter pub get

init-example:
	cd example && fvm flutter pub get

clean:
	fvm flutter clean
	cd example && fvm flutter clean

# ─── Quality ───────────────────────────────────────────────────────────────────
format:
	fvm dart format --line-length 100 .

analyze:
	fvm flutter analyze

test: init
	fvm flutter test

# format check + analyze + test, as CI would run it
check: format analyze test

# ─── Example app ─────────────────────────────────────────────────────────────────
run-example: init-example
	cd example && fvm flutter run

build-example-apk: init-example
	cd example && fvm flutter build apk --debug
