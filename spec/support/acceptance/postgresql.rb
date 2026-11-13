# frozen_string_literal: true

# puppetlabs/postgresql is needed for manage_db but is not a metadata dependency
RSpec.configure do |c|
  c.before :suite do
    install_puppet_module_via_pmt_on(hosts, 'puppetlabs-postgresql')
  end
end
