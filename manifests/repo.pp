# @api private
class artifactory::repo (
  $edition = $artifactory::edition,
) {
  case $facts['os']['family'] {
    'RedHat': {
      $baseurl = $edition ? {
        'pro'   => 'https://releases.jfrog.io/artifactory/artifactory-pro-rpms/',
        default => 'https://releases.jfrog.io/artifactory/artifactory-rpms/',
      }

      yumrepo { 'Artifactory':
        enabled       => true,
        baseurl       => $baseurl,
        descr         => 'Artifactory',
        repo_gpgcheck => true,
        gpgcheck      => false,
        gpgkey        => "${baseurl}/repodata/repomd.xml.key",
      }
    }
    'Debian': {
      $repo = $edition ? {
        'pro'   => 'artifactory-pro-debs',
        default => 'artifactory-debs',
      }

      apt::source { 'artifactory':
        location => "https://releases.jfrog.io/artifactory/${repo}",
        release  => $facts['os']['distro']['codename'],
        repos    => 'main',
        key      => {
          'name'   => 'artifactory.asc',
          'source' => 'https://releases.jfrog.io/artifactory/api/gpg/key/public',
        },
        include  => { 'src' => false },
      }
    }
    default: {
      fail("Unsupported OS family ${facts['os']['family']} for managing the Artifactory repository")
    }
  }
}
