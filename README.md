# puppet/artifactory

[![Build Status](https://github.com/voxpupuli/puppet-artifactory/workflows/CI/badge.svg)](https://github.com/voxpupuli/puppet-artifactory/actions?query=workflow%3ACI)
[![Release](https://github.com/voxpupuli/puppet-artifactory/actions/workflows/release.yml/badge.svg)](https://github.com/voxpupuli/puppet-artifactory/actions/workflows/release.yml)
[![Puppet Forge](https://img.shields.io/puppetforge/v/puppet/artifactory.svg)](https://forge.puppetlabs.com/puppet/artifactory)
[![Puppet Forge - downloads](https://img.shields.io/puppetforge/dt/puppet/artifactory.svg)](https://forge.puppetlabs.com/puppet/artifactory)
[![Puppet Forge - endorsement](https://img.shields.io/puppetforge/e/puppet/artifactory.svg)](https://forge.puppetlabs.com/puppet/artifactory)
[![Puppet Forge - scores](https://img.shields.io/puppetforge/f/puppet/artifactory.svg)](https://forge.puppetlabs.com/puppet/artifactory)
[![puppetmodule.info docs](http://www.puppetmodule.info/images/badge.png)](http://www.puppetmodule.info/m/puppet-artifactory)
[![Apache-2 License](https://img.shields.io/github/license/voxpupuli/puppet-artifactory.svg)](LICENSE)

## Table of Contents

1. [Description](#description)
1. [Setup - The basics of getting started with artifactory](#setup)
    * [What artifactory affects](#what-artifactory-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with artifactory](#beginning-with-artifactory)
1. [Usage - Configuration options and additional functionality](#usage)
1. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
1. [Limitations - OS compatibility, etc.](#limitations)
1. [Development - Guide for contributing to the module](#development)

## Description

This module manages the installation of Artifactory, (OSS or commercial editions).

It has been developed for and tested with Artifactory 7 on RHEL 8, but should also function on later versions of RHEL (and its clones).

## Setup

### What artifactory affects

The module installs Artifactory 7 from RPM (RedHat family) or DEB (Debian and Ubuntu) packages.
It manages Artifactory's `system.yaml` configuration file, the `master.key` file, `binarystore.xml` and settings within the `artifactory.system.properties` file.

It has been developed for use with `PostgreSQL` as Artifactory's backend database and will, by default, manage the creation of the database instance too.

### Setup Requirements

When `manage_db` is `true`, (the default), `puppetlabs/postgresql` will be used to configure the database instance.
It is still recommended that before declaring the `artifactory` module, you include your own `postgresql` profile to tune and customise the PostgreSQL installation.

Artifactory 7 includes its own Java distribution and JDBC drivers, such that you shouldn't need to include any puppet code to manage these.

### Beginning with artifactory

The module has a single public class. At its simplest, and assuming your server has Internet access and is able to reach JFrog's public yum/apt servers, you can simply include the base class to get a working installation.

```puppet
include artifactory
```

All defaults will be used. This will include a default installation of postgreSQL to host Artifactory's database.
In practice, there are several customisations you will probably want to make.

#### Controlling which version is installed

The `edition` parameter defaults to `oss`.  It can be set to `pro` to install the commercial edition of Artifactory. The setting influences the repository configured when `manage_repo` is set to `true`, as well as the default for the `package_name` parameter.

The `package_version` parameter can be used to specify an exact package version, (the package version), of Artifactory to install.

If you set `manage_repo` to `false`, the module will not configure the yum or apt repository, but will still expect the appropriate package to be available.

#### PostgreSQL

When `manage_db` is `true`, the `artifactory::db` class will be included to ensure PostgreSQL is installed by using the `puppetlabs/postgresql` module.

The code will `include postgresql::globals`, but in order to customise the PostgreSQL installation you will want to declare this with your own options *before* including artifactory.

Detailed instructions on how to customise PostgreSQL with the `puppetlabs/postgresl` module are outside of the scope for this document, but as a very simple example you could use PostgreSQL 16 with 2 GB configured for the important `shared_buffers` setting.

```puppet
class { 'postgresql::globals':
  encoding          => 'utf8',
  locale            => 'en_US.utf8',
  version           => '16',
  manage_dnf_module => true,
}

postgresql::server::config_entry { 'shared_buffers':
  value => '2048MB',
}

class { 'artifactory':
  db_password => Sensitive($some_secret_db_password), # Specify the db password instead of letting the module generate and cache its own.
}
```

#### Using a different database

JFrog *strongly* recommend using PostgreSQL. This module should allow you to use one of the other supported databases too, but there has been very limited testing, and `manage_db` must be set to `false`.

```puppet
class { 'artifactory':
  manage_db   => false,
  db_type     => 'mariadb',
  db_port     => '3306',
  db_host     => 'my-mariadb.example.com',
  db_password => Sensitive($some_secret_db_password),
}
```

(You can of course also use an external PostgreSQL by setting `manage_db` to `false` and specifying `db_host` parameters etc.)

#### Customising the JDBC database URL

The module will automatically set a JDBC database URL in `system.yaml` with a format based on the `db_type`.  If you need to use a custom URL, (perhaps to set some advanced JDBC driver properties), you can use the `db_url` parameter.

#### JVM Memory and other settings

By default, the module will configure the Java process heap size to be 2GB. This can be customised by using the `jvm_max_heap_size` parameter (and `jvm_min_heap_size` if you don't want the minimum to be the same as the maximum value). Other JVM options can be configured using the `jvm_extra_args` parameter.

In this example, the heap size is set to 8GB, and JMX based monitoring has been configured on the `localhost` interface.

```puppet
class { 'artifactory':
  jvm_max_heap_size => '8G',
  jvm_extra_args    => {
    '-Dcom.sun.management.jmxremote',
    '-Dcom.sun.management.jmxremote.port=9000',
    '-Dcom.sun.management.jmxremote.local.only=true',
    '-Dcom.sun.management.jmxremote.authenticate=false',
    '-Dcom.sun.management.jmxremote.ssl=false',
  },
}
```

#### The Binary Store configuration

By default, the module will configure the `binarystore.xml` file with the very basic default local filesystem configuration.
If you need something more complicated, (for example because you're storing artifacts in AWS S3), you must pass the complete `binarystore.xml` content as a string in the `binary_store_config_xml` parameter.

#### Custom `system.yaml` configuration

The various database related parameters and the `jvm` parameters influence the contents of `system.yaml`. If you need to override any of this configuration file, you can use the `additional_system_config` parameter.
This hash will be merged to form the final `system.yaml` configuration. It can be used to overwrite _any_ of the configuration including any of that related to the database configuration, (for example if you needed to specify the name of a custom JDBC driver).

In this example, it is being used to change the listen address of various Artifactory services. (Note, configuring a reverse proxy is outside the scope of this module).

```puppet
class { 'artifactory':
  additional_system_config => {
    'router'      => {
      'entrypoints' => {
        'externalHost' => '127.0.0.1',
      },
    },
    'artifactory' => {
      'tomcat' => {
        'connector' => {
          'extraConfig' => 'address="127.0.0.1"',
        },
      },
    },
  },
}
```

#### Management of the `artifactory` group and user

If you need to manage the `artifactory` user's UID and GID, then use the `uid` and (optionally `gid`) parameters. When not set, the user and group will simply be created by the RPM's post install script.

#### Customising System Properties

On some occasions, you might need to configure a setting in `artifactory.system.properties`.  You can use the `system_properties` parameter for this. Augeas will be used to either set or remove a property from this file.

For example, to remove an old, no longer used setting, use `undef` as its value.

```puppet
class { 'artifactory':
  system_properties => {
    'artifactory.gems.compact.index.enabled' => undef, # Remove this old setting that isn't needed/wanted in modern Artifactory 7.
  },
}
```

#### The `master.key`

Artifactory uses the `master.key` to encrypt secrets in the database and importantly to also encrypt plaintext secrets it finds in `system.yaml`, especially the database password.

You can set the `master_key` parameter to specify your own 128 or 256 bit AES key, (as a 32 or 64 character hex string). If you don't use your own key, Artifactory will generate one when it first starts. Updating the key is *not* supported.

This module is clever enough to not replace the encrypted values Artifactory generates in the `system.yaml` with the original plaintext passwords on each puppet run.

#### Support for Sensitive and Deferred secrets

Both the `master_key` and `db_password` parameters will correctly accept `Sensitive` values and automatically redact them from logs etc.
`Deferred` values are also supported by _this_ module, but unfortunately, if `manage_db` is set to `true`, `db_password` currently doesn't work if `Deferred` due to a bug in the `puppetlabs/postgresql` module.

#### Access Configuration

The `artifactory_access_setting` type can be used to configure [access](https://jfrog.com/help/r/jfrog-installation-setup-documentation/access-yaml-configuration) settings.

The name of each resource should be the configuration setting in dotted notation. Set the `value` parameter to the required value.

For example, enforcing two of the security related settings.

```puppet
artifactory_access_setting { 'security.password-policy.length':
  value => 8,
}

artifactory_access_setting { 'security.authentication.ldap.referral-strategy':
  value => 'ignore',
}
```

## Reference

[Puppet Strings REFERENCE.md](REFERENCE.md)

## Limitations

* Tested on CentOS 8
* Puppet/Openvox 7 or greater.
* Artifactory 7 only. This module won't manage upgrading from version 6 for you.
* Not all configuration files can currently be managed.  For example, content of the `access.config.latest.yml` configuration file.
* This module doesn't manage the contents of Artifactory. It can not be used to create repositories, configure authentication sources, manage permissions etc.

## Development

This module is maintained by [Vox Pupuli](https://voxpupuli.org/).

It was written by [Alex Fisher](https://github.com/alexjfisher) and is licensed under the Apache-2.0 License.
