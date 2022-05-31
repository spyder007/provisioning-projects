chmod go-w ~/
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

sudo mkdir /myagent 
cd /myagent

export AZP_AGENT_USE_LEGACY_HTTP=true
sudo wget "$MS_AGENT_URL/$MS_AGENT_FILENAME"
sudo tar zxvf ./$MS_AGENT_FILENAME
sudo chmod -R 777 /myagent
./config.sh --unattended  --url "$MS_AGENT_ORG_URL" --auth pat --token "$MS_AGENT_PAT" --pool "$MS_AGENT_POOL_NAME"
sudo ./svc.sh install
sudo ./svc.sh start
exit 0