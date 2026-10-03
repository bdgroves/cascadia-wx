# CASCADIA-WX - make (fetch + build + run), make build, make run,
# make normals (30 years of balloons, about 20 minutes), make clean
FC     = gfortran
FFLAGS = -O2 -Wall -Wno-character-truncation

.PHONY: all fetch build run normals clean

all: fetch build run

fetch:
	python3 fetch_wx.py || [ $$? -lt 8 ]

build: cascadia-wx

cascadia-wx: CWX_PHYS.f90 CASCADIA-WX.f90
	$(FC) $(FFLAGS) -o $@ $^

normals-bin: CWX_PHYS.f90 NORMALS.f90
	$(FC) $(FFLAGS) -o $@ $^

normals: normals-bin
	python3 fetch_wx.py --history
	./normals-bin
	rm -rf history

run: cascadia-wx
	./cascadia-wx || [ $$? -lt 8 ]
	@cat cascadia-wx-report.txt

clean:
	rm -f cascadia-wx cascadia-wx.exe normals-bin *.mod soundings_raw.csv fetch_status.csv
