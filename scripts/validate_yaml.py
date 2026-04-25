import yaml, sys
try:
    yaml.safe_load(open('/mnt/c/code-server-enterprise/docker-compose.yml'))
    print('YAML OK')
except yaml.YAMLError as e:
    print('YAML ERROR:', e)
    sys.exit(1)
