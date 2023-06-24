Rock Runner
===========

A Boulder Dash® clone for the Commander X16, written in [Prog8](https://prog8.readthedocs.io) (requires version 9 or later).

Original Boulder Dash® in 1984 by First Star Software, created by Peter Liepa and Chris Gray.
Copyright by BBG Entertainment GmbH.

The graphics tile set is from MIT-licensed GDash and is based on Boulder Rush by Michael Kowalski / Miksoft. See below for links.


Custom Level files ('cavesets')
===============================

The "CAVES" subdirectory contains a bunch of fan-made cavesets,
but also the original Boulderdash 1 and Boulderdash 2 caves.
The game starts up with the Boulderdash 1 caves, but you can load a different cave set from the menu if you want.
You can also add more cavesets in this subdirectory by simply copying the files in there. Make sure the files are in the ASCII 'BDCFF' format.
Hundreds of cavesets can be freely obtained from https://boulderdash.nl/ in the 'BDCFF' section.

TODO
----
- it is still possible to eat diamonds that are not getting added to the score. Cave 4 (butterflies). Not fixed now that the cx16 registers are properly saved in the IRQ handler :(
- add the menu to load a different caveset
- finish BDCFF parsing
- mashing te keyboard at the menu screen can make the game reset the system with error code $83 in $0400. Most likely because something is messing with the ram bank while the decoding is still running, or the IRQ routine destroying one of the Cx16 virtual registers. MIGHT BE FIXED NOW
- sometimes the next level doesn't completely scroll into the center (for example cave B after finishing A)
- fix the C64 slime permeability calculation, it's not rnd() > permeability? it's some form of AND ? " every bit has an equal value, more bits set to 1 means more delay."
- change the highscore tracking: 1 table per caveset, save it (in another dir?) a score file per caveset file.
- touch up the tileset to real 16x16 graphics? starting with diamonds and boulders then Rockford then the rest
- selectable tilesets?  also add the real c64 retro tileset with adjustable palette?
- easter egg (how to trigger?): replace butterfly with X16 logo
- better title tune (@Crisps?)
- better sound effects for the random sounds (Use random tones from a scale rather than totally random frequencies?)
- tweak the controls to also register button presses outside of cavescan - does this make it more responsive?
- fix the remaining TODOs in the code.


Development Resources
---------------------

* https://www.boulder-dash.nl/
* https://www.elmerproductions.com/sp/peterb/
* https://www.elmerproductions.com/sp/peterb/BDCFF/index.html
* https://www.elmerproductions.com/sp/peterb/insideBoulderdash.html
* https://www.elmerproductions.com/sp/peterb/sounds.html#Theme%20tune
* http://www.emeraldmines.net/BDCFF/
* https://www.boulder-dash.nl/bdcff_doc.html
* http://www.gratissaugen.de/erbsen/bdcff.html
* http://www.gratissaugen.de/erbsen/BD-Inside-FAQ.html
* https://codeincomplete.com/articles/javascript-boulderdash/
* https://codeincomplete.com/articles/javascript-boulderdash/objects.pdf
* https://codeincomplete.com/articles/javascript-boulderdash/sounds.pdf
* https://codeincomplete.com/articles/javascript-boulderdash/raw_cave_data.pdf
* http://www.bd-fans.com/FanStuff.html#Programming
* https://github.com/Agetian/bouldercaves
* https://github.com/irmen/bouldercaves
* https://bitbucket.org/czirkoszoltan/gdash/
* https://bitbucket.org/czirkoszoltan/gdash/src/c8390151fb1181a7d8c81df8eab67ab2cbf018e0/src/misc/helptext.cpp#lines-223


### GDash license (for Boulder Rush tileset):


Copyright (c) 2007-2013, Czirkos Zoltan https://bitbucket.org/czirkoszoltan/gdash

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
