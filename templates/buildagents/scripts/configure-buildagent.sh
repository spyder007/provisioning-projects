chmod go-w ~/
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

sudo mkdir /myagent 
cd /myagent

# Copy environment variables to .env file
env | grep Image >> /myagent/.env
env | grep ANDROID_ >> /myagent/.env
env | grep JAVA_ >> /myagent/.env
env | grep HOMEBREW_ >> /myagent/.env
env | grep ANT_ >> /myagent/.env
env | grep GRADLE_ >> /myagent/.env
env | grep LEIN_ >> /myagent/.env
env | grep CONDA >> /myagent/.env
env | grep PIPX_ >> /myagent/.env
env | grep AGENT_ >> /myagent/.env
env | grep EDGEWEBDRIVER >> /myagent/.env
env | grep CHROMEWEBDRIVER >> /myagent/.env
env | grep CHROME_BIN >> /myagent/.env
env | grep BOOTSTRAP_ >> /myagent/.env
env | grep GHCUP_ >> /myagent/.env
env | grep NVM_ >> /myagent/.env
env | grep SELENIUM_ >> /myagent/.env
env | grep SWIFT_ >> /myagent/.env
env | grep VCPKG_ >> /myagent/.env
env | grep DOTNET_ >> /myagent/.env
env | grep LANG >> /myagent/.env
env | grep M2_ >> /myagent/.env
env | grep VSTS_ >> /myagent/.env
env | grep LD_ >> /myagent/.env
env | grep PERL5LIB >> /myagent/.env

export AZP_AGENT_USE_LEGACY_HTTP=true
sudo wget "$MS_AGENT_URL/$MS_AGENT_FILENAME"
sudo tar zxvf ./$MS_AGENT_FILENAME
sudo chmod -R 777 /myagent
./config.sh --unattended  --url "$MS_AGENT_ORG_URL" --auth pat --token "$MS_AGENT_PAT" --pool "$MS_AGENT_POOL_NAME"
sudo ./svc.sh install
sudo ./svc.sh start
exit 0