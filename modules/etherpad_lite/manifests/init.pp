# == Class: etherpad_lite
#
# Class to install etherpad lite. Puppet acts a lot like a package manager
# through this class.
#
# To use etherpad lite you will want the following includes:
# include etherpad_lite
# include etherpad_lite::mysql # necessary to use mysql as the backend
# include etherpad_lite::site # configures etherpad lite instance
# include etherpad_lite::apache # will add reverse proxy on localhost
# The defaults for all the classes should just work (tm)
#
#
class etherpad_lite (
  $ep_user          = 'eplite',
  $base_log_dir     = '/var/log',
  $base_install_dir = '/opt/etherpad-lite',
  $nodejs_version   = 'v0.6.16',
  $eplite_version   = '',
  $ep_headings = false
) {

  # where the modules are, needed to easily install modules later
  $modules_dir = "${base_install_dir}/etherpad-lite/node_modules"
  $path = "/usr/bin:/bin:/usr/local/bin:${base_install_dir}/etherpad-lite"

  user { $ep_user:
    shell   => '/sbin/nologin',
    home    => "${base_log_dir}/${ep_user}",
    system  => true,
    gid     => $ep_user,
    require => Group[$ep_user],
  }

  group { $ep_user:
    ensure => present,
  }

  # Below is what happens when you treat puppet as a package manager.
  # This is probably bad, but it works and you don't need to roll .debs.
  file { $base_install_dir:
    ensure => directory,
    group  => $ep_user,
    mode   => '0664',
  }

  vcsrepo { "${base_install_dir}/nodejs":
    ensure   => present,
    provider => git,
    source   => 'https://github.com/joyent/node.git',
    revision => $nodejs_version,
    require  => [
        Package['git'],
        File[$base_install_dir],
    ],
  }

  package { [
      'gzip',
      'curl',
      'python',
      'libssl-dev',
      'pkg-config',
      'abiword',
      'build-essential',
    ]:
    ensure => present,
  }

  package { ['nodejs', 'npm']:
    ensure => purged,
  }

  buildsource { "${base_install_dir}/nodejs":
    timeout => 900, # 15 minutes
    creates => '/usr/local/bin/node',
    require => [
      Package['gzip'],
      Package['curl'],
      Package['python'],
      Package['libssl-dev'],
      Package['pkg-config'],
      Package['build-essential'],
      Vcsrepo["${base_install_dir}/nodejs"],
    ],
  }

  # Allow existing install to exist without modifying its git repo.
  # But give the option to specify versions for new installs.
  if $eplite_version != '' {
    vcsrepo { "${base_install_dir}/etherpad-lite":
      ensure   => present,
      provider => git,
      source   => 'https://github.com/ether/etherpad-lite.git',
      owner    => $ep_user,
      revision => $eplite_version,
      require  => Package['git'],
    }
  } else {
    vcsrepo { "${base_install_dir}/etherpad-lite":
      ensure   => present,
      provider => git,
      source   => 'https://github.com/Pita/etherpad-lite.git',
      owner    => $ep_user,
      require  => Package['git'],
    }
  }

  exec { 'install_etherpad_dependencies':
    command     => './bin/installDeps.sh',
    path        => $path,
    user        => $ep_user,
    cwd         => "${base_install_dir}/etherpad-lite",
    environment => "HOME=${base_log_dir}/${ep_user}",
    require     => [
      Vcsrepo["${base_install_dir}/etherpad-lite"],
      Buildsource["${base_install_dir}/nodejs"],
    ],
    before      => File["${base_install_dir}/etherpad-lite/settings.json"],
    creates     => "${base_install_dir}/etherpad-lite/node_modules",
  }

  if $ep_headings == true {
    # install the test install plugin
    # This seesm to be needed to get
    exec {'npm install ep_fintest':
      cwd     => $modules_dir,
      path    => $path,
      creates => "${modules_dir}/ep_fintest",
      require => Exec['install_etherpad_dependencies']
    } ->

    # install the headings plugin
    exec {'npm install ep_headings':
      cwd     => $modules_dir,
      path    => $path,
      creates => "${modules_dir}/ep_headings",
      require => Exec['install_etherpad_dependencies']
    }
  }

  file { '/etc/init/etherpad-lite.conf':
    ensure  => present,
    content => template('etherpad_lite/upstart.erb'),
    replace => true,
    owner   => 'root',
  }

  file { '/etc/init.d/etherpad-lite':
    ensure => link,
    target => '/lib/init/upstart-job',
  }

  file { "${base_log_dir}/${ep_user}":
    ensure => directory,
    owner  => $ep_user,
  }
  # end package management ugliness
}
