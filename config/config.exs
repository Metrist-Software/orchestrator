import Config

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, {:awscli, :system, 30}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, {:awscli, :system, 30}, :instance_role]
