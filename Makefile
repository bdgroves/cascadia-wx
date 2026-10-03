# CASCADIA-WX - make (fetch + build + run), make build, make run, make clean
FC     = gfortran
FFLAGS = -O2 -Wall -Wno-character-truncation

.PHONY: all fetch build run clean

all: fetch build run

fetch:
	python3 fetch_wx.py || [ $$? -lt 8 ]

build: cascadia-wx

cascadia-wx: CASCADIA-WX.f90
	$(FC) $(FFLAGS) -o $@ $<

run: cascadia-wx
	./cascadia-wx || [ $$? -lt 8 ]
	@cat cascadia-wx-report.txt

clean:
	rm -f cascadia-wx cascadia-wx.exe *.mod soundings_raw.csv fetch_status.csv
