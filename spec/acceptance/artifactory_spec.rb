# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'artifactory' do
  shared_examples 'a running artifactory' do
    describe yumrepo('Artifactory') do
      it { is_expected.to be_enabled }
    end

    describe package('jfrog-artifactory-oss') do
      it { is_expected.to be_installed }
    end

    describe service('artifactory') do
      it { is_expected.to be_enabled }
      it { is_expected.to be_running }
    end

    describe service('postgresql') do
      it { is_expected.to be_running }
    end

    describe file('/opt/jfrog/artifactory/var/etc/system.yaml') do
      it { is_expected.to be_file }
      it { is_expected.to be_owned_by 'artifactory' }
      it { is_expected.to be_mode 640 }
      its(:content) { is_expected.to match %r{jdbc:postgresql://localhost:5432/artifactory} }
    end

    describe file('/opt/jfrog/artifactory/var/etc/artifactory/binarystore.xml') do
      it { is_expected.to be_file }
      it { is_expected.to be_owned_by 'artifactory' }
    end

    # Artifactory takes a while to start
    describe command('timeout 600 sh -c "until curl -sf http://127.0.0.1:8082/artifactory/api/system/ping; do sleep 5; done"') do
      its(:exit_status) { is_expected.to eq 0 }
      its(:stdout) { is_expected.to eq 'OK' }
    end

    [8081, 8082].each do |p|
      describe port(p) do
        it { is_expected.to be_listening }
      end
    end
  end

  context 'with default parameters' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) { 'include artifactory' }
    end

    it_behaves_like 'a running artifactory'

    describe file('/opt/jfrog/artifactory/var/etc/system.yaml') do
      its(:content) { is_expected.to match %r{-Xms2G -Xmx2G} }
    end
  end

  context 'with custom parameters' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          class { 'artifactory':
            jvm_max_heap_size        => '1G',
            jvm_extra_args           => ['-Xss1m'],
            additional_system_config => {
              'shared' => {
                'logging' => {
                  'consoleLog' => {
                    'enabled' => false,
                  },
                },
              },
            },
            system_properties        => {
              'artifactory.search.maxResults' => '1000',
            },
          }
        PUPPET
      end
    end

    it_behaves_like 'a running artifactory'

    describe file('/opt/jfrog/artifactory/var/etc/system.yaml') do
      its(:content) { is_expected.to match %r{-Xms1G -Xmx1G -Xss1m} }
      its(:content) { is_expected.to match %r{consoleLog:\n\s+enabled: false} }
    end

    describe file('/opt/jfrog/artifactory/var/etc/artifactory/artifactory.system.properties') do
      its(:content) { is_expected.to match %r{^artifactory\.search\.maxResults=1000$} }
    end
  end
end
