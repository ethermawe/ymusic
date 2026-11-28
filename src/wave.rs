use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Choice {
    pub name: String,
    pub seed: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Group {
    pub key: String,
    pub name: String,
    pub choices: Vec<Choice>,
}

/// Only expose options with an explicit session seed supplied by the server.
/// In particular, do not guess seeds for old numeric mood/energy scales.
pub fn groups(response: &Value) -> Vec<Group> {
    let mut groups = Vec::new();
    if let Some(restrictions) = response["settingRestrictions"].as_object() {
        for (key, value) in restrictions {
            let Some(values) = value["possibleValues"]
                .as_array()
                .or_else(|| value["values"].as_array())
            else {
                continue;
            };
            let choices: Vec<_> = values
                .iter()
                .filter_map(|v| {
                    let seed = v["serializedSeed"].as_str()?;
                    let name = v["name"].as_str()?;
                    // The UI already provides an explicit "Без фильтра" option.
                    if v["unspecified"].as_bool() == Some(true)
                        || matches!(
                            name.trim().to_lowercase().as_str(),
                            "любое" | "любой" | "любая" | "любые"
                        )
                    {
                        return None;
                    }
                    (!seed.is_empty() && seed.len() <= 256 && !name.is_empty()).then(|| Choice {
                        name: name.into(),
                        seed: seed.into(),
                    })
                })
                .take(60)
                .collect();
            if !choices.is_empty() {
                groups.push(Group {
                    key: key.clone(),
                    name: value["name"]
                        .as_str()
                        .unwrap_or(match key.as_str() {
                            "diversity" => "Разнообразие",
                            "language" => "Язык",
                            "moodEnergy" => "Настроение",
                            "mood" => "Настроение",
                            "energy" => "Энергия",
                            _ => key,
                        })
                        .into(),
                    choices,
                });
            }
        }
    }
    groups
}

pub fn validate(
    groups: &[Group],
    selections: &std::collections::HashMap<String, String>,
) -> anyhow::Result<Vec<String>> {
    let mut seeds = Vec::new();
    for (key, seed) in selections {
        anyhow::ensure!(
            groups
                .iter()
                .any(|g| &g.key == key && g.choices.iter().any(|c| &c.seed == seed)),
            "Фильтр больше недоступен. Обновите настройки волны."
        );
        seeds.push(seed.clone());
    }
    seeds.sort();
    seeds.dedup();
    Ok(seeds)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn uses_server_seeds_and_rejects_unknown_choices() {
        let groups = groups(&json!({"settingRestrictions": {
            "diversity": {"name": "Разнообразие", "possibleValues": [
                {"name": "Открытия", "serializedSeed": "settingDiversity:discover"},
                {"name": "Old option", "value": "guess"}]},
            "energy": {"type": "discrete-scale", "min": {"value": 0}, "max": {"value": 4}}
        }}));
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].choices.len(), 1);
        let selected = std::collections::HashMap::from([(
            "diversity".into(),
            "settingDiversity:discover".into(),
        )]);
        assert_eq!(
            validate(&groups, &selected).unwrap(),
            vec!["settingDiversity:discover"]
        );
        assert!(
            validate(
                &groups,
                &std::collections::HashMap::from([("diversity".into(), "bad:seed".into())])
            )
            .is_err()
        );
    }

    #[test]
    fn omits_unspecified_options_but_keeps_real_filters() {
        let result = groups(&json!({"settingRestrictions": {
            "language": {"possibleValues": [
                {"name": "Любой", "serializedSeed": "language:any"},
                {"name": "По умолчанию", "serializedSeed": "language:default", "unspecified": true},
                {"name": "Русский", "serializedSeed": "language:ru"}
            ]},
            "mood": {"possibleValues": [
                {"name": "Любое", "serializedSeed": "mood:any"},
                {"name": "Спокойное", "serializedSeed": "mood:calm"}
            ]}
        }}));
        assert_eq!(result.len(), 2);
        assert!(result.iter().all(|g| g.choices.len() == 1));
        assert!(
            validate(&result, &std::collections::HashMap::new())
                .unwrap()
                .is_empty()
        );
        assert!(
            validate(
                &result,
                &std::collections::HashMap::from([("language".into(), "language:any".into())])
            )
            .is_err()
        );
    }
}
