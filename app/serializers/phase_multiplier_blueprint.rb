# frozen_string_literal: true

# Public projection of one PhaseMultiplier: the machine key (phase), the current
# multiplier (as a number, not the DB decimal string), and a localized label.
# Labels live in i18n (scoring.phases.*).
class PhaseMultiplierBlueprint < Blueprinter::Base
  fields :phase

  field :multiplier do |row|
    row.multiplier.to_f
  end

  field :label do |row|
    I18n.t("scoring.phases.#{row.phase}")
  end
end
