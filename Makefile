.PHONY: test lint format clean

# Default target
all: test

# Test target - runs all tests using plenary
test:
	nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Lint target - runs stylua check
lint:
	stylua --color always --check lua

# Format target - formats code with stylua  
format:
	stylua lua

# Clean target - removes temporary files
clean:
	find . -name "*.tmp" -delete
	find . -name "*.log" -delete

# Help target
help:
	@echo "Available targets:"
	@echo "  test     - Run all tests"
	@echo "  lint     - Check code formatting"
	@echo "  format   - Format code with stylua"
	@echo "  clean    - Remove temporary files"
	@echo "  help     - Show this help message"