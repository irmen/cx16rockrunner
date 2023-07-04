Rock Runner
===========

A Boulder Dash® clone for the Commander X16, written in [Prog8](https://prog8.readthedocs.io) (requires version 9.1 or later).

Original Boulder Dash® in 1984 by First Star Software, created by Peter Liepa and Chris Gray.
Copyright by BBG Entertainment GmbH.

The graphics tile set is from MIT-licensed GDash and is based on Boulder Rush by Michael Kowalski / Miksoft. See below for links.


Custom Level files ('cavesets')
===============================

The "CAVES" subdirectory contains a bunch of fan-made cavesets,
but also the original Boulderdash 1 and Boulderdash 2 caves.
The game starts up with the Boulderdash 1 caves, but you can load a different cave set from the menu if you want.
You can also add more cavesets in this subdirectory by simply copying the files in there. Make sure the files are in the BDCFF text format.
Hundreds of cavesets can be freely obtained from https://boulderdash.nl/ in the BDCFF section.

TODO
----
- *bug:* it is still possible to eat diamonds that are not getting added to the score. BD1 Cave 4 (butterflies). Some obscure timing/cavescan order issue?
- possible bug: check behavior of Cave speed/Cave delay (see handler() routine comment)
- cosmetic: test: tweak the controls to also register joystick buttons outside of cavescan - does this make it more responsive?
- cosmetic: allow joypad to select caveset too, not only via keyboard
- feature: scroll long filename list in the load caveset screen
- feature: touch up the tileset to real 16x16 graphics? starting with diamonds and boulders then Rockford then the rest
- feature: selectable tilesets?  also add the real c64 retro tileset with adjustable palette?
- feature: easter egg (how to trigger?): replace butterfly with X16 logo
- feature: better title tune (@Crisps?)
- feature: better sound effects for the random sounds (Use random tones from a scale rather than totally random frequencies?)
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

