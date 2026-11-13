# @summary Installs and configures Artifactory
#
# @param manage_repo
#   Whether to manage the artifactory yum (RedHat family) or apt (Debian family) repository
# @param edition
#   Controls which version of Artifactory is installed
# @param package_name
#   The Artifactory package name
# @param package_version
#   The package version of the Artifactory package, (or `latest`, `installed` etc.)
# @param db_type
#   The database type. Artifactory works with other databases, but strongly recommends only using `postgresql`
# @param db_host
#   The host of database server housing Artifactory's database
# @param db_name
#   The name of the database (or SERVICE for `oracle` databases)
# @param db_user
#   The username used to connect to the database
# @param db_port
#   The TCP port the database listens on
# @param db_password
#   The password of the `db_user`. By default a random password will be generated, and cached on your puppet server. Only use when you have a single Puppetserver
# @param db_url
#   Instead of allowing this Puppet module to set the JDBC database URL based on, `db_type`, `db_host`, `db_port` and `db_name`, manaully override the URL by setting this parameter
# @param additional_system_config
#   A hash of any additional configuration. This will be merged into the default configuration, and database configuration when building the `system.yaml` file.
# @param manage_db
#   Whether to install and configure Artifactory's database. Only supported for `db_type` postgresql
# @param uid
#   If set, the UID to use when managing the `artifactory` user.  If not set, the module will not manage the user
# @param gid
#   The GID to use for the `artifactory` group when managing the `artifactory` user. Will default to the same as the `uid`
# @param master_key
#   If set, this will be used at the value for the `master.key`. This should not be changed after Artifactory has been deployed.
# @param binary_store_config_xml
#   The contents to be used for a custom binary-store.xml file. When not set, the default file-system configuration will be used.
# @param jvm_max_heap_size
#   The Java Maximum Heap Size. Used in the `-Xmx` java option.
# @param jvm_min_heap_size
#   The Java Minimum Heap Size. Used in the '-Xms' java option. Defaults to the `jvm_max_heap_size`.
# @param jvm_extra_args
#   Any extra java options. For example, setting the stack size with `-Xss1m`
# @param system_properties
#   A hash of Artifactory 'system properties'. These will be added to the `artifactory.system.properties` file. Set a value to `undef` if you want to remove it from the file.
class artifactory (
  Boolean           $manage_repo     = true,
  Enum['oss','pro'] $edition         = 'oss',
  String[1]         $package_name    = "jfrog-artifactory-${edition}",
  String[1]         $package_version = 'installed',

  Enum[
    'derby',
    'mariadb',
    'mssql',
    'mysql',
    'oracle',
    'postgresql'
  ]                   $db_type = 'postgresql',
  Boolean             $manage_db = true,
  Stdlib::Host        $db_host = 'localhost',
  String[1]           $db_name = 'artifactory',
  String[1]           $db_user = 'artifactory',
  Stdlib::Port        $db_port = 5432,
  Variant[
    Sensitive[String[1]],
    String[1]
  ]                   $db_password = extlib::cache_data('artifactory', 'db_password', extlib::random_password(16)),
  Optional[String[1]] $db_url = undef,

  Hash              $additional_system_config = {},
  Optional[Integer] $uid = undef,
  Optional[Integer] $gid = $uid,

  Optional[
    Variant[
      Sensitive[Pattern[/\A(\h{32}|\h{64})\z/]],
      Pattern[/\A(\h{32}|\h{64})\z/]
    ]
  ] $master_key = undef,

  Optional[String[1]] $binary_store_config_xml = undef,

  String[1]        $jvm_max_heap_size  = '2G',
  String[1]        $jvm_min_heap_size  = $jvm_max_heap_size,
  Array[String[1]] $jvm_extra_args     = [],

  Hash $system_properties = {},
) {
  if $manage_repo {
    contain artifactory::repo
    Class['artifactory::repo'] -> Class['artifactory::install']
  }

  if $manage_db {
    unless $db_type == 'postgresql' { fail('Only postgresql is supported when `manage_db` is `true`') }
    contain artifactory::db
    Class['artifactory::db'] -> Class['artifactory::service']
  }

  if $uid and $gid {
    contain artifactory::user
    Class['artifactory::user'] -> Class['artifactory::install']
  }

  contain artifactory::install
  contain artifactory::config
  contain artifactory::service

  Class['artifactory::install']
  -> Class['artifactory::config']
  ~> Class['artifactory::service']
}
