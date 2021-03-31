sudo mkdir /myagent 
cd /myagent
sudo wget "$MS_AGENT_URL/$MS_AGENT_FILENAME"
sudo tar zxvf ./$MS_AGENT_FILENAME
sudo chmod -R 777 /myagent
/myagent/config.sh --unattended  --url "$MS_AGENT_ORG_URL" --auth pat --token "$MS_AGENT_PAT" --pool "$MS_AGENT_POOL_NAME"
sudo /myagent/svc.sh install
sudo /myagent/svc.sh start
exit 0