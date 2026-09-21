# Workspace slides and screenshot release — September 21, 2026

The effects UI's **Full slide** option inherited the glide travel percentage.
With travel set to 10%, it emitted `slide 10%` for all three regular workspace
animation declarations. Pure slides keep workspace content opaque, so reduced
travel puts outgoing and incoming content in overlapping screen positions.
The installed Hyprland revision's [workspace animation implementation](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/animation/WorkspaceAnimationController.cpp)
sets the slide translation from this percentage while retaining alpha 1.

The backend now emits 100% travel for opaque horizontal and vertical slides in
both custom and profile motion. The UI displays 100% and disables travel editing
for Full slide. Glide styles retain adjustable travel; switching styles retains
the saved glide value. Profile curves, timing and other animation families stay
unchanged. Fade also disables the irrelevant travel control.

For screenshots, Copy, Search and OCR kept the frozen selection overlays and
input grab active until cropping and the action worker completed. All still-image
actions now hide the panels as soon as processing starts. The session continues
to own the frozen image and worker. Success dismisses the session; failure restores
the selection and its error message for retry. Recording behavior is unchanged.

## Validation

- Four regression tests evaluate the generated Lua, checking opaque slides,
  horizontal/vertical glides, fades, profile timing and unaffected animation
  families. Run `python3 tests/test_workspace_motion.py -v` with Lua installed.
- The installed compositor accepted 18 generated configurations: custom/profile
  motion, slide/slidefade/fade, and 0/10/100% travel.
- Both changed QML components compiled successfully.
- A private virtual KWin plus nested Hyprland session exercised the actual
  selector, screenshot helper, image crop and private clipboard. With a deliberate
  one-second clipboard delay, the overlay released at 148 ms after selection,
  versus 1,390 ms before. Work still completed around 1,331 ms after the fix;
  the improvement is desktop availability during processing. Both images had the
  expected 600 × 400 size. An injected clipboard failure restored the selector,
  and retry succeeded.
- Native captures verified a full-screen slide in both directions using two
  tiled test windows. This confirms corrected travel, not a frame-time or physical
  desktop smoothness improvement. The simplified fixture did not independently
  reproduce every reported delayed-paint symptom.
- Live readback showed `slide 100%` for workspaces, workspacesIn and workspacesOut,
  with no Hyprland configuration errors. The selected profile, saved effects
  settings, EasyEffects state and player state were preserved.

The clipboard timing above is an isolated fault-injection comparison, not a
measurement of the user's ordinary screenshot latency. Motion blur, glass,
glow, spring tuning and profile speed were retained. Visual acceptance on the
physical desktop remains separate from these configuration and integration checks.
