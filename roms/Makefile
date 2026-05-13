# Makefile - GNU Makefile
#
# Copyright (c) 2026 Andy Karpov.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

SRC_DIVMMC=src/esxdos.rom src/128-0.rom src/128-1.rom
SRC_ZC=src/gluk.rom src/trdos.rom src/128p-0.rom src/128p-1.rom
IMAGES=29c010.rom

all: $(IMAGES)

29c010.rom: $(SRC_DIVMMC)
	cat src/gluk.rom > 29c010.rom
	cat src/trdos611_vspider512.rom >> 29c010.rom
	cat src/128p-0.rom >> 29c010.rom
	cat src/128p-1.rom >> 29c010.rom
	cat src/esxdos.rom >> 29c010.rom
	cat src/esxdos.rom >> 29c010.rom
	cat src/diagrom.rom >> 29c010.rom
	cat src/128-0.rom >> 29c010.rom
	cat src/128-1.rom >> 29c010.rom

clean:
	rm -f $(IMAGES)

