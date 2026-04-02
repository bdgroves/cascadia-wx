# CASCADIA-WX - Pacific Northwest Mountain Weather Analysis
# GFortran Makefile

FC       = gfortran
FFLAGS   = -O2 -Wall -lm
TARGET   = cascadia-wx
SOURCE   = CASCADIA-WX.f90

.PHONY: all fetch build run clean check

all: fetch build run

fetch:
	@echo "Fetching live NRCS SNOTEL + NOAA surface data..."
	python3 fetch_wx.py

build:
	@echo "Compiling $(SOURCE)..."
	$(FC) $(FFLAGS) -o $(TARGET) $(SOURCE)
	@echo "Build complete: ./$(TARGET)"

run: $(TARGET)
	@echo "Running CASCADIA-WX..."
	./$(TARGET)
	@echo ""
	@echo "--- REPORT ---"
	@cat cascadia-wx-report.txt

clean:
	@rm -f $(TARGET) cascadia-wx-report.txt analysis.csv
	@echo "Cleaned."

check:
	@which gfortran > /dev/null 2>&1 || \
		(echo "ERROR: gfortran not found." && \
		 echo "  Ubuntu/Debian: sudo apt install gfortran" && \
		 echo "  macOS:         brew install gcc" && \
		 exit 1)
	@which python3 > /dev/null 2>&1 || \
		(echo "ERROR: python3 not found." && exit 1)
	@echo "GFortran: $$(gfortran --version | head -1)"
	@echo "Python:   $$(python3 --version)"
