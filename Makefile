.PHONY: help build run stop restart smoke reset-onboarding run-onboarding test-release-signing test-window test-window-ui test-window-focus test-flux test-alt-tab test-search test-dictation test-dictation-cleanup-benchmark test-dictation-live test-dictation-codex-capture-live test-dictation-secure-live test-dictation-multidisplay-live test-dictation-model-live test-dictation-installed-models-live test-dictation-shortcut-live test-dictation-opaque-paste-live test-dictation-unicode-typing-live test-dictation-real-microphone-live release release-dry clean

PROJECT := Gojo.xcodeproj
SCHEME := Gojo
CONFIGURATION := Debug
DERIVED_DATA_PATH := .build/DerivedData
APP_PATH := $(DERIVED_DATA_PATH)/Build/Products/$(CONFIGURATION)/Gojo.app

help:
	@echo "Gojo local commands:"
	@echo "  make build       Build the Debug macOS app"
	@echo "  make run         Build, replace any running Gojo, then launch"
	@echo "  make stop        Stop running Gojo dev app processes"
	@echo "  make restart     Stop, build, and launch the app"
	@echo "  make smoke       Build, launch, verify process, then stop"
	@echo "  make reset-onboarding  Wipe config + permissions so onboarding runs again"
	@echo "  make run-onboarding    Reset, then build + launch into onboarding"
	@echo "  make test-release-signing Verify Sparkle sandbox entitlements in release artifacts"
	@echo "  make test-window Run window management regression checks"
	@echo "  make test-window-ui Run Windows tab UI regression checks"
	@echo "  make test-window-focus Run focused-window provider regression checks"
	@echo "  make test-flux   Run flux night shift regression checks"
	@echo "  make test-alt-tab Run window switcher selection regression checks"
	@echo "  make test-search Run search calculator/fuzzy-matcher regression checks"
	@echo "  make test-dictation Run local dictation regressions and benchmark scorer checks"
	@echo "  make test-dictation-cleanup-benchmark Compare fast OpenRouter cleanup models (paid)"
	@echo "  make test-dictation-live Verify focused insertion in TextEdit and Safari (requires Accessibility)"
	@echo "  make test-dictation-codex-capture-live Verify capture against a running Codex window"
	@echo "  make test-dictation-secure-live Verify secure fields are rejected"
	@echo "  make test-dictation-multidisplay-live Verify capture on a secondary display"
	@echo "  make test-dictation-model-live Run synthesized speech through the app model and TextEdit"
	@echo "  make test-dictation-installed-models-live Test every installed model without downloading"
	@echo "  make test-dictation-shortcut-live Exercise the real Control+Option event tap"
	@echo "  make test-dictation-opaque-paste-live Verify opaque app paste and focus safety"
	@echo "  make test-dictation-unicode-typing-live Verify guarded Unicode typing and clipboard safety"
	@echo "  make test-dictation-real-microphone-live Verify real microphone capture, transcription, and insertion"
	@echo ""
	@echo "Release:"
	@echo "  make release VERSION=x.y.z      Cut a private signed/notarized release (see RELEASING.md)"
	@echo "  make release VERSION=x.y.z ARGS=--public  Also publish to R2 + appcast"
	@echo "  make release-dry VERSION=x.y.z  Build + sign + notarize without publishing"
	@echo ""
	@echo "  make clean       Remove local build artifacts"

release:
	@test -n "$(VERSION)" || (echo "Usage: make release VERSION=x.y.z [ARGS=--public|--adhoc]"; exit 2)
	@./scripts/release.sh $(VERSION) $(ARGS)

release-dry:
	@test -n "$(VERSION)" || (echo "Usage: make release-dry VERSION=x.y.z [ARGS=--public|--adhoc]"; exit 2)
	@DRY_RUN=1 ./scripts/release.sh $(VERSION) $(ARGS)

build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination 'platform=macOS' \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		build

run: build
	$(MAKE) stop
	@# GOJO_LICENSE forces the license state and keeps this build away from the
	@# license Keychain entirely, so it can't strand the installed app's license.
	@# Values: lifetime | monthly | trial | trial:<days> | locked
	@if [ -n "$(GOJO_LICENSE)" ]; then \
		open --env "GOJO_LICENSE=$(GOJO_LICENSE)" "$(APP_PATH)"; \
	else \
		open "$(APP_PATH)"; \
	fi

stop:
	@for pattern in \
		'/Gojo\.app/Contents/MacOS/Gojo' \
		'/Gojo\.app/Contents/XPCServices/GojoXPCHelper\.xpc/Contents/MacOS/GojoXPCHelper' \
		'/Gojo\.app/Contents/Resources/mediaremote-adapter\.pl' \
		'/Gojo\.app/Contents/Frameworks/Sparkle\.framework/.*/Downloader'; do \
		pids=$$(pgrep -f "$$pattern" || true); \
		if [ -n "$$pids" ]; then kill $$pids 2>/dev/null || true; fi; \
	done
	@sleep 0.5
	@for pattern in \
		'/Gojo\.app/Contents/MacOS/Gojo' \
		'/Gojo\.app/Contents/XPCServices/GojoXPCHelper\.xpc/Contents/MacOS/GojoXPCHelper' \
		'/Gojo\.app/Contents/Resources/mediaremote-adapter\.pl' \
		'/Gojo\.app/Contents/Frameworks/Sparkle\.framework/.*/Downloader'; do \
		pids=$$(pgrep -f "$$pattern" || true); \
		if [ -n "$$pids" ]; then kill -9 $$pids 2>/dev/null || true; fi; \
	done

restart: run

reset-onboarding:
	@./scripts/reset-onboarding.sh $(ARGS)

run-onboarding: reset-onboarding run

test-release-signing:
	./tests/release_signing_regression.sh

smoke:
	./tests/gojo_smoke.sh

test-window:
	./tests/window_management_regression.sh

test-window-ui:
	./tests/window_power_view_regression.sh

test-window-focus:
	./tests/focused_window_provider_regression.sh

test-flux:
	./tests/flux_regression.sh

test-alt-tab:
	./tests/alt_tab_regression.sh

test-search:
	./scripts/test_search_engine.sh

test-dictation: build
	./tests/dictation_regression.sh
	./tests/openrouter_dictation_regression.sh
	./tests/dictation_offline_policy_regression.sh
	bash ./tests/dictation_capture_probe_regression.sh
	./tests/text_insertion_xpc_regression.sh
	./tests/dictation_unicode_typing_regression.sh
	bash ./tests/dictation_live_harness_regression.sh
	./tests/dictation_benchmark_regression.sh
	bash ./tests/dictation_cleanup_benchmark_regression.sh

test-dictation-cleanup-benchmark:
	python3 scripts/benchmarks/benchmark_cleanup.py

test-dictation-live:
	./tests/dictation_live_e2e.sh native
	./tests/dictation_live_e2e.sh browser

test-dictation-codex-capture-live:
	bash ./tests/dictation_codex_capture_live_e2e.sh

test-dictation-secure-live:
	bash ./tests/dictation_secure_capture_live_e2e.sh

test-dictation-multidisplay-live:
	@status=0; bash ./tests/dictation_multidisplay_capture_live_e2e.sh || status=$$?; \
		test "$$status" -eq 0 -o "$$status" -eq 77

test-dictation-model-live:
	./tests/dictation_model_live_e2e.sh

test-dictation-installed-models-live:
	./tests/dictation_installed_models_live_e2e.sh

test-dictation-shortcut-live:
	./tests/dictation_event_tap_shortcut_live_e2e.sh

test-dictation-opaque-paste-live:
	./tests/dictation_opaque_paste_live_e2e.sh

test-dictation-unicode-typing-live:
	./tests/dictation_unicode_typing_live_e2e.sh

test-dictation-real-microphone-live:
	./tests/dictation_real_microphone_live_e2e.sh

clean:
	rm -rf "$(DERIVED_DATA_PATH)"
