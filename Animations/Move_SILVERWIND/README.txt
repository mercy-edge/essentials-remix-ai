DO NOT USE THESE FILES WITH "IMPORT ANIM" IN THE ANIMATION EDITOR

The files silverwind-anim.anm and Move_SILVERWIND.anm in this folder were
created by external Ruby tools. They use Ruby 3 Marshal format and WILL FAIL
with "invalid or could not be loaded" / dump format error.

TO APPLY THE CUSTOM SILVER WIND ANIMATION:

1. Play test the game (F12)
2. Press F9 > Debug > Other editors... > Import Silver Wind animation
3. Confirm the success message

That writes directly to slot 243 using the game's own save format.

After step 3, the game also creates Move_SILVERWIND_imported.anm in the
project root — that file IS valid for Import Anim if you need it later.
