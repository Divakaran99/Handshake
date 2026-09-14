"""Godspeed anthropomorphism subscale (semantic differential anchors).

Cite the original instrument in any publication:
  Bartneck, C., Kulic, D., Croft, E., & Zoghbi, S. (2009). Measurement
  instruments for the anthropomorphism, animacy, likeability, perceived
  intelligence, and safety of robots. International Journal of Social Robotics.

Only anchor pairs are encoded here. Reproduce the full instrument from the
source when you run a real study, and record which version you used.
"""

import from instruments.instrument { Scale, ScaleItem }

glob GODSPEED_ANTHROPOMORPHISM: Scale = Scale(
    name="Godspeed I - Anthropomorphism",
    citation="Bartneck et al. (2009), Int. J. Social Robotics",
    points=5,
    items=[
        ScaleItem(key="fake_natural", anchor_low="Fake", anchor_high="Natural"),
        ScaleItem(key="machine_human", anchor_low="Machinelike", anchor_high="Humanlike"),
        ScaleItem(key="uncons_conscious", anchor_low="Unconscious", anchor_high="Conscious"),
        ScaleItem(key="artif_lifelike", anchor_low="Artificial", anchor_high="Lifelike"),
        ScaleItem(key="rigid_elegant", anchor_low="Moving rigidly", anchor_high="Moving elegantly")
    ]
);
