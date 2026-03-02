include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/midway-auth.hcl"
  expose = true
}

inputs = {
  domain_name               = "mlkeita.people.aws.dev"
  subject_alternative_names = ["*.mlkeita.people.aws.dev"]
  create_hosted_zone        = false # SuperNova creates the hosted zone during domain registration
  cognito_user_pool_name    = "ml-clusters-auth"
  cognito_domain_prefix     = "ml-clusters-mlkeita"

  # Federate credentials: set via TF_VAR_federate_client_id and TF_VAR_federate_client_secret
  # federate_client_id     = <from env>
  # federate_client_secret = <from env>

  service_configs = {
    argocd = {
      callback_urls = ["https://argocd.mlkeita.people.aws.dev/oauth2/idpresponse"]
      logout_urls   = ["https://argocd.mlkeita.people.aws.dev"]
    }
    atlantis = {
      callback_urls = ["https://atlantis.mlkeita.people.aws.dev/oauth2/idpresponse"]
      logout_urls   = ["https://atlantis.mlkeita.people.aws.dev"]
    }
  }
}
