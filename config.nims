# Keep the FlowBrigade Toolkit on Nim ARC by default, matching RocheDB's
# memory-management profile. The implementation should avoid owning reference
# cycles; cross-structure links should use ids or indexes rather than owning
# back-references.
switch("mm", "arc")
