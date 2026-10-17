# @api private
class artifactory::config (
  Enum['derby', 'mariadb', 'mssql', 'mysql', 'oracle', 'postgresql'] $db_type = 'postgresql',
  Stdlib::Host        $db_host                  = $artifactory::db_host,
  String[1]           $db_name                  = $artifactory::db_name,
  String[1]           $db_user                  = $artifactory::db_user,
  Stdlib::Port        $db_port                  = $artifactory::db_port,
  Variant[
    Sensitive[String[1]],
    String[1]
  ]                   $db_password              = $artifactory::db_password,
  Optional[String[1]] $db_url                   = $artifactory::db_url,
  Hash                $additional_system_config = $artifactory::additional_system_config,
  Optional[String[1]] $binary_store_config_xml  = $artifactory::binary_store_config_xml,

  Variant[
    Undef,
    Sensitive[Pattern[/\A(\h{32}|\h{64})\z/]],
    Pattern[/\A(\h{32}|\h{64})\z/]
  ] $master_key = $artifactory::master_key,

  String[1]        $jvm_max_heap_size = $artifactory::jvm_max_heap_size,
  String[1]        $jvm_min_heap_size = $artifactory::jvm_min_heap_size,
  Array[String[1]] $jvm_extra_args    = $artifactory::jvm_extra_args,

  Hash $system_properties = $artifactory::system_properties
) {
  $jfrog_home = '/opt/jfrog'
  $datadir = "${jfrog_home}/artifactory/var"

  $base_config = {
    'configVersion' => 1,
    'shared'        => {
      'security' => undef,
      'node'     => undef,
      'database' => {},
      'user'     => 'artifactory',
    },
    'access'        => undef,
  }

  if $db_url {
    $_db_url = $db_url
  } else {
    $_db_url = $db_type ? {
      'postgresql'      => "jdbc:postgresql://${db_host}:${db_port}/${db_name}",
      /(mariadb|mysql)/ => "jdbc:${db_type}://${db_host}:${db_port}/${db_name}?characterEncoding=UTF-8&elideSetAutoCommits=true&useSSL=false",
      'mssql'           => "jdbc:sqlserver://${db_host}:${db_port};databaseName=${db_name};sendStringParametersAsUnicode=false;applicationName=Artifactory Binary Repository",
      'oracle'          => "jdbc:oracle:thin:@//[${db_host}][${db_port}]/${db_name}",
    }
  }

  $db_driver = $db_type ? {
    'postgresql' => 'org.postgresql.Driver',
    'mariadb'    => 'org.mariadb.jdbc.Driver',
    'mysql'      => 'com.mysql.jdbc.Driver',
    'mssql'      => 'com.microsoft.sqlserver.jdbc.SQLServerDriver',
    'oracle'     => 'oracle.jdbc.OracleDriver',
  }

  if $db_type == 'postgresql' {
    $allow_non_postgresql = false
  } else {
    $allow_non_postgresql = true
  }

  if $db_type == 'derby' {
    $db_config = {
      'allowNonPostgresql' => $allow_non_postgresql,
    }
  } else {
    $db_config = {
      'allowNonPostgresql' => $allow_non_postgresql,
      'type'               => $db_type,
      'driver'             => $db_driver,
      'url'                => $_db_url,
      'username'           => $db_user,
      'password'           => $db_password,
    }
  }

  $extra_java_opts = ([
    "-Xms${jvm_min_heap_size}",
    "-Xmx${jvm_max_heap_size}",
  ] + $jvm_extra_args).unique.join(' ')

  $master_key_file = "${datadir}/etc/security/master.key"

  if $master_key {
    file { "${datadir}/etc/security":
      ensure => directory,
      owner  => 'artifactory',
      group  => 'artifactory',
      mode   => '0640',
    }

    file { $master_key_file:
      ensure  => file,
      owner   => 'artifactory',
      group   => 'artifactory',
      mode    => '0640',
      content => Sensitive($master_key),
    }

    $key = $master_key
  } else {
    $key = $master_key_file
  }

  artifactory_yaml_file { "${datadir}/etc/system.yaml":
    ensure => present,
    config => Sensitive($base_config.deep_merge(
      { 'shared' => { 'database' => $db_config, 'extraJavaOpts' => $extra_java_opts } },
      $additional_system_config
    )),
    owner  => 'artifactory',
    group  => 'artifactory',
    mode   => '0640',
    key    => $key,
  }

  if $binary_store_config_xml {
    $binary_store_content = $binary_store_config_xml
  } else {
    $binary_store_content = file('artifactory/default-binarystore.xml')
  }

  artifactory_xml_file { "${datadir}/etc/artifactory/binarystore.xml":
    ensure  => present,
    owner   => 'artifactory',
    group   => 'artifactory',
    mode    => '0640',
    content => Sensitive($binary_store_content),
    key     => $key,
  }

  $changes = $system_properties.map |$key, $value| {
    if $value == undef {
      "rm \"${key}\""
    } else {
      "set \"${key}\" \"${value}\""
    }
  }

  unless $changes.empty {
    augeas { 'artifactory.system.properties':
      context => "/files${datadir}/etc/artifactory/artifactory.system.properties",
      incl    => "${datadir}/etc/artifactory/artifactory.system.properties",
      lens    => 'Properties.lns',
      changes => $changes,
    }
  }

  artifactory_access_settings { "${datadir}/etc/access": }
}
