# Balmatchum DEV Launch Screen Assets

The source DEV splash was delivered as an opaque image on black. A connected
edge flood fill (`maxRGB < 45`) removes only the outer near-black background,
preserving enclosed dark outlines, the full illustration, and the bottom
`-dev-` label. The resulting image is stored at 1x, 2x, and 3x.
`LaunchScreenDev.storyboard` displays it with aspect fit over the shared cream
`LaunchBackground` color.
