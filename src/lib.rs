use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::{path::PathBuf, process::Command};
use strum::{AsRefStr, Display, EnumIter, EnumString};

#[derive(Debug, Deserialize, Serialize, Clone, Copy, EnumIter, EnumString, AsRefStr, Display)]
pub enum Category {
    Web,
    Pwn,
    Crypto,
    Misc,
    Reverse,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ChallengeDockerConfig {
    pub name: String,
    pub author: String,
    pub category: Category,
    pub tags: Vec<String>,
    pub description: String,
    pub attachments: Vec<String>,
    pub is_dynamic_flag: bool,
    pub points: i32,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ChallengeDockerManager {
    pub challenge_docker_config: ChallengeDockerConfig,
    pub challenge_path: PathBuf,
    pub docker_compose_yml: PathBuf,
    pub docker_compose_project_name: String,
    pub main_container_name: String,
    pub id: u64,
}

impl ChallengeDockerManager {
    fn run_command(
        command: &str,
        args: &[&str],
        env_vars: Option<HashMap<&str, &str>>,
    ) -> Result<Vec<u8>, String> {
        let mut cmd = Command::new(command);
        cmd.args(args);

        // 设置环境变量
        if let Some(envs) = env_vars {
            for (key, value) in envs {
                cmd.env(key, value);
            }
        }

        let output = cmd
            .output()
            .map_err(|e| format!("Failed to execute {}: {}", command, e))?;

        if !output.status.success() {
            return Err(format!(
                "{} failed: {}",
                command,
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        Ok(output.stdout)
    }

    pub fn check_docker_env() -> Result<(), String> {
        // docker installed?
        ChallengeDockerManager::run_command("docker", &["--version"], None)?;

        // docker-compose
        ChallengeDockerManager::run_command("docker-compose", &["--version"], None)?;

        // docker permission
        ChallengeDockerManager::run_command("docker", &["ps"], None)?;

        Ok(())
    }

    pub fn new(challenge_path: PathBuf, id: u64) -> Result<Self, String> {
        let content = std::fs::read_to_string(challenge_path.join("FloatCTF.toml"))
            .map_err(|e| format!("Failed to read FloatCTF.toml: {}", e))?;

        let config: ChallengeDockerConfig = toml::from_str(&content)
            .map_err(|e| format!("Failed to parse the FloatCTF.toml: {}", e))?;

        let docker_compose_yml = challenge_path.join("docker-compose.yml");
        if !docker_compose_yml.exists() {
            return Err(format!("The {} has no docker-compose.yml", config.name));
        }

        // check attachments is exist
        for attachment in &config.attachments {
            let attachment_path = challenge_path.join("attachments").join(attachment);
            if !attachment_path.exists() {
                return Err(format!(
                    "The {} has no attachment: {}",
                    config.name, attachment
                ));
            }
        }

        Ok(ChallengeDockerManager {
            id,
            docker_compose_yml,
            docker_compose_project_name: format!("challenge-project-{}-{}", id, config.name),
            main_container_name: format!("challenge-{}-{}", config.name, id),
            challenge_path,
            challenge_docker_config: config,
        })
    }

    pub fn build(&self) -> Result<(), String> {
        ChallengeDockerManager::run_command(
            "docker-compose",
            &[
                "--file",
                &self.docker_compose_yml.to_string_lossy(),
                "build",
            ],
            None,
        )?;
        Ok(())
    }

    // return the map port
    pub fn up(&self, flag: String) -> Result<u64, String> {
        let mut env_vars = HashMap::new();
        if self.challenge_docker_config.is_dynamic_flag {
            env_vars.insert("FLAG", flag.as_str());
        }

        let binding = self.id.to_string();
        env_vars.insert("ID", &binding);

        ChallengeDockerManager::run_command(
            "docker-compose",
            &[
                "--file",
                &self.docker_compose_yml.to_string_lossy(),
                "--project-name",
                &self.docker_compose_project_name,
                "up",
                "--detach",
            ],
            Some(env_vars),
        )?;

        let output = ChallengeDockerManager::run_command(
            "docker",
            &[
                "inspect",
                "--format",
                "{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}{{end}}",
                &self.main_container_name,
            ],
            None,
        )?;

        let s = String::from_utf8(output).map_err(|e| format!("Invalid UTF-8 in output: {}", e))?;
        let port = s.trim();
        port.parse::<u64>()
            .map_err(|e| format!("Failed to parse port: {}", e))
    }

    pub fn down(&self) -> Result<(), String> {
        ChallengeDockerManager::run_command(
            "docker-compose",
            &[
                "--file",
                &self.docker_compose_yml.to_string_lossy(),
                "--project-name",
                &self.docker_compose_project_name,
                "down",
                "--volumes",
                "--timeout=1",
            ],
            None,
        )?;
        Ok(())
    }

    pub fn get_static_flag(&self) -> Result<String, String> {
        if self.challenge_docker_config.is_dynamic_flag {
            return Err("The challenge is not static flag".to_string());
        }
        let dot_env = self.challenge_path.join(".env");
        let content =
            std::fs::read_to_string(dot_env).map_err(|e| format!("Failed to read .env: {}", e))?;
        for line in content.lines() {
            if let Some(rest) = line.strip_prefix("FLAG=") {
                return Ok(rest.trim().to_string());
            }
        }
        Err("FLAG not found in .env".to_string())
    }
}

#[cfg(test)]
mod test_cdm {
    use super::*;

    #[test]
    fn check_docker() {
        if let Err(e) = ChallengeDockerManager::check_docker_env() {
            panic!("Docker environment check failed: {}", e);
        }
    }

    #[test]
    fn check_init() {
        let cdm = ChallengeDockerManager::new("./challenges/comment".into(), 1);

        if let Err(e) = cdm {
            panic!("Failed to  init the ChallengeDockerManager:{}", e);
        }

        let cdm = cdm.unwrap();
        println!("{:?}", cdm);
    }

    #[test]
    fn check_build() {
        let cdm = ChallengeDockerManager::new("./challenges/comment".into(), 1);

        if let Err(e) = cdm {
            panic!("Failed to  init the ChallengeDockerManager:{}", e);
        }

        let cdm = cdm.unwrap();
        cdm.build().unwrap();
    }

    #[test]
    fn check_up() {
        let cdm = ChallengeDockerManager::new("./challenges/comment".into(), 1);

        if let Err(e) = cdm {
            panic!("Failed to  init the ChallengeDockerManager:{}", e);
        }

        let cdm = cdm.unwrap();
        let flag = {
            if cdm.challenge_docker_config.is_dynamic_flag {
                "flag{this_is_a_test_flag}".to_string()
            } else {
                cdm.clone().get_static_flag().unwrap()
            }
        };

        let port = cdm.up(flag).unwrap();
        println!("{}", port);
    }

    #[test]
    fn check_down() {
        let cdm = ChallengeDockerManager::new("./challenges/comment".into(), 1);

        if let Err(e) = cdm {
            panic!("Failed to  init the ChallengeDockerManager:{}", e);
        }

        let cdm = cdm.unwrap();
        cdm.down().unwrap();
    }

    #[test]
    fn check_static_flag() {
        let cdm = ChallengeDockerManager::new("./challenges/comment".into(), 1);

        if let Err(e) = cdm {
            panic!("Failed to  init the ChallengeDockerManager:{}", e);
        }

        let cdm = cdm.unwrap();
        let flag = cdm.get_static_flag().unwrap();
        println!("{}", flag)
    }
}
