chmod go-w ~/
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

sudo mkdir /myagent 
cd /myagent

touch .env
# Copy environment variables to .env file
env | grep Image >> .env
env | grep ANDROID_ >> .env
env | grep JAVA_ >> .env
env | grep HOMEBREW_ >> .env
env | grep ANT_ >> .env
env | grep GRADLE_ >> .env
env | grep LEIN_ >> .env
env | grep CONDA >> .env
env | grep PIPX_ >> .env
env | grep AGENT_ >> .env
env | grep EDGEWEBDRIVER >> .env
env | grep CHROMEWEBDRIVER >> .env
env | grep CHROME_BIN >> .env
env | grep BOOTSTRAP_ >> .env
env | grep GHCUP_ >> .env
env | grep NVM_ >> .env
env | grep SELENIUM_ >> .env
env | grep SWIFT_ >> .env
env | grep VCPKG_ >> .env
env | grep DOTNET_ >> .env
env | grep LANG >> .env
env | grep M2_ >> .env
env | grep VSTS_ >> .env
env | grep LD_ >> .env
env | grep PERL5LIB >> .env

export AZP_AGENT_USE_LEGACY_HTTP=true
sudo wget "$MS_AGENT_URL/$MS_AGENT_FILENAME"
sudo tar zxvf ./$MS_AGENT_FILENAME
sudo chmod -R 777 /myagent
./config.sh --unattended  --url "$MS_AGENT_ORG_URL" --auth pat --token "$MS_AGENT_PAT" --pool "$MS_AGENT_POOL_NAME"
sudo ./svc.sh install
sudo ./svc.sh start
exit 0