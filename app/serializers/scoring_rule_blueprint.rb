# frozen_string_literal: true

# Public projection of one ScoringRule: the machine key (rule_type), the current
# points value, and a localized, human label so the SPA can render the rules
# page without hardcoding any copy. Labels live in i18n (scoring.rule_types.*).
class ScoringRuleBlueprint < Blueprinter::Base
  fields :rule_type, :points

  field :label do |rule|
    I18n.t("scoring.rule_types.#{rule.rule_type}")
  end
end
