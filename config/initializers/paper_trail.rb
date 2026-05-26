# PaperTrail audit-log configuration.
#
# Association tracking is intentionally disabled: in PaperTrail 17 it lives in
# the separate paper_trail-association_tracking gem, which we do not install, so
# only direct attribute changes (including object_changes) are recorded. This is
# the behaviour the spec asks for ("track_associations = false").
#
# Per-model `has_paper_trail` activation happens in later (Phase 1) tickets;
# the actor (whodunnit) is set from the current user in ApplicationController.
