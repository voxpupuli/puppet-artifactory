# frozen_string_literal: true

require 'openssl'
require 'base64'
require 'yaml'

require 'puppet/type/file/owner'
require 'puppet/type/file/group'
require 'puppet/type/file/mode'

Puppet::Type.newtype(:artifactory_yaml_file) do
  @doc = <<-DOC
    @summary
      Used to generates the system.yaml file but replaces its content only if encrypted fields don't decrypt to strings matching the plaintext versions from `content`
    @api private
  DOC

  attr_accessor :replace_file_content

  ensurable do
    defaultvalues

    defaultto { :present }
  end

  def exists?
    self[:ensure] == :present
  end

  newparam(:path, namevar: true) do
    validate do |value|
      raise ArgumentError, 'File paths must be fully qualified' unless Puppet::Util.absolute_path?(value, :posix)
    end
  end

  newparam(:owner, parent: Puppet::Type::File::Owner) do
    desc <<-DOC
      Specifies the owner of the destination file. Valid options: a string containing a username or integer containing a uid.
    DOC
  end

  newparam(:group, parent: Puppet::Type::File::Group) do
    desc <<-DOC
      Specifies a permissions group for the destination file. Valid options: a string containing a group name or integer containing a
      gid.
    DOC
  end

  newparam(:mode, parent: Puppet::Type::File::Mode) do
    desc <<-DOC
      Specifies the permissions mode of the destination file. Valid options: a string containing a permission mode value in octal notation.
    DOC
  end

  newparam(:show_diff, boolean: true, parent: Puppet::Parameter::Boolean) do
    desc <<-DOC
      Specifies whether to set the show_diff parameter for the file resource. Useful for hiding secrets stored in hiera from insecure
      reporting methods.
    DOC
  end

  newparam(:key) do
    validate do |value|
      raise ArgumentError, 'key must be an absolute path to a key file, or the raw hex key string' unless Puppet::Util.absolute_path?(value, :posix) || value.chomp =~ %r{\A(\h{32}|\h{64})\z}
    end

    munge do |value|
      if Puppet::Util.absolute_path?(value, :posix)
        if File.exist?(value)
          File.read(value).chomp
        else
          debug "#{value} doesn't exist"
          nil
        end
      else
        value.chomp
      end
    end
  end

  newparam(:config) do
    munge do |value|
      current = retrieve
      target  = YAML.dump(deep_unwrap(value))

      if current.nil? || resource[:key].nil?
        resource.replace_file_content = true
        target
      else
        decrypted_content = deep_transform_strings(YAML.safe_load(current), %r{\A\h{6}\.aesgcm(128|256)\.[A-Za-z0-9_-]+\z}) { |s| decrypt_string(s, resource[:key]) }
        if decrypted_content == deep_unwrap(value)
          debug 'decrypted_content matches target state'
          current
        else
          debug 'decrypted_content DID NOT match target state'
          resource.replace_file_content = true
          target
        end
      end
    end

    def retrieve
      if File.exist?(resource.parameter(:path).value)
        File.read(resource.parameter(:path).value)
      else
        debug "file doesn't exist yet"
        nil
      end
    end

    def deep_transform_strings(obj, regex, &transform)
      case obj
      when Hash
        obj.transform_values { |v| deep_transform_strings(v, regex, &transform) }
      when Array
        obj.map { |e| deep_transform_strings(e, regex, &transform) }
      when String
        regex.match?(obj) ? transform.call(obj) : obj
      else
        obj
      end
    end

    def deep_unwrap(obj)
      if obj.is_a?(Puppet::Pops::Types::PSensitiveType::Sensitive)
        resource.parameter(:config).sensitive = true
        obj = obj.unwrap
      end

      case obj
      when Hash
        obj.transform_values { |v| deep_unwrap(v) }
      when Array
        obj.map { |v| deep_unwrap(v) }
      else
        obj
      end
    end

    def decrypt_string(string, master_key_hex)
      _label, alg, payload_b64 = string.split('.', 3)
      key = [master_key_hex].pack('H*')

      if alg == 'aesgcm256'
        expected_key_bytesize = 32
        cipher = 'aes-256-gcm'
      else
        expected_key_bytesize = 16
        cipher = 'aes-128-gcm'
      end

      if key.bytesize != expected_key_bytesize
        warning 'master key size did not match size used to encrypt data'
        return string
      end

      begin
        buf = Base64.urlsafe_decode64(payload_b64)

        iv  = buf[0, 12]
        ct  = buf[12...-16]
        tag = buf[-16, 16]

        c = OpenSSL::Cipher.new(cipher)
        c.decrypt
        c.key = key
        c.iv = iv
        c.auth_tag = tag
        c.update(ct) + c.final
      rescue StandardError => e
        warning "Error decrypting string in Artifactory yaml: #{e.inspect}"
        string
      end
    end
  end

  autorequire(:file) do
    [self[:path]]
  end

  def generate
    file_opts = {
      ensure: (self[:ensure] == :absent) ? :absent : :file,
    }

    %i[
      path
      owner
      group
      mode
      show_diff
    ].each do |param|
      file_opts[param] = self[param] unless self[param].nil?
    end

    excluded_metaparams = %i[before notify require subscribe tag]

    Puppet::Type.metaparams.each do |metaparam|
      file_opts[metaparam] = self[metaparam] unless self[metaparam].nil? || excluded_metaparams.include?(metaparam)
    end

    [Puppet::Type.type(:file).new(file_opts)]
  end

  def eval_generate
    if replace_file_content
      catalog.resource("File[#{self[:path]}]")[:content] = self[:config]
      catalog.resource("File[#{self[:path]}]").parameter(:content).sensitive = true if parameter(:config).sensitive
    end
    [catalog.resource("File[#{self[:path]}]")]
  end

  def set_sensitive_parameters(sensitive_parameters) # rubocop:disable Naming/AccessorMethodName
    if sensitive_parameters.include?(:config)
      sensitive_parameters.delete(:config)
      parameter(:config).sensitive = true
    end

    if sensitive_parameters.include?(:key)
      sensitive_parameters.delete(:key)
      parameter(:key).sensitive = true
    end

    super
  end
end
