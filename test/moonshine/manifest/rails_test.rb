require File.dirname(__FILE__) + '/../../test_helper.rb'

class Moonshine::Manifest::RailsTest < Test::Unit::TestCase

  def setup
    @manifest = Moonshine::Manifest::Rails.new
  end

  def test_is_executable
    assert @manifest.executable?
  end

  def test_loads_gems_from_config_hash
    @manifest.configure(:gems => [ { :name => 'jnewland-pulse', :source => 'http://gems.github.com/' } ])
    @manifest.rails_gems
    assert_not_nil Moonshine::Manifest::Rails.configatron.gems
    Moonshine::Manifest::Rails.configatron.gems.each do |gem|
      assert_not_nil gem_resource = @manifest.puppet_resources[Puppet::Type::Package][gem[:name]]
      assert_equal gem[:source], gem_resource.params[:source].value
      assert_equal :gem, gem_resource.params[:provider].value
    end
  end

  def test_creates_directories
    config = {
      :application => 'foo',
      :user => 'foo',
      :deploy_to => '/srv/foo'
    }
    @manifest.configure(config)
    @manifest.rails_directories
    assert_not_nil shared_dir = @manifest.puppet_resources[Puppet::Type::File]["/srv/foo/shared"]
    assert_equal :directory, shared_dir.params[:ensure].value
    assert_equal 'foo', shared_dir.params[:owner].value
    assert_equal 'foo', shared_dir.params[:group].value
  end

  def test_installs_apache
    @manifest.apache_server
    assert_not_nil apache = @manifest.puppet_resources[Puppet::Type::Service]["apache2"]
    assert_equal @manifest.package('apache2-mpm-worker').to_s, apache.params[:require].value.to_s
  end

  def test_enables_mod_rewrite
    @manifest.apache_server
    assert_not_nil apache = @manifest.puppet_resources[Puppet::Type::Exec]["a2enmod rewrite"]
  end

  def test_installs_passenger_gem
    @manifest.passenger_configure_gem_path
    @manifest.passenger_gem
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Package]["passenger"]
  end

  def test_installs_passenger_module
    @manifest.passenger_configure_gem_path
    @manifest.passenger_apache_module
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Package]['apache2-threaded-dev']
    assert_not_nil @manifest.puppet_resources[Puppet::Type::File]['/etc/apache2/mods-available/passenger.load']
    assert_not_nil @manifest.puppet_resources[Puppet::Type::File]['/etc/apache2/mods-available/passenger.conf']
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Exec].find { |n, r| r.params[:command].value == '/usr/sbin/a2enmod passenger' }
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Exec].find { |n, r| r.params[:command].value == '/usr/bin/ruby -S rake clean apache2' }
  end

  def test_configures_passenger_vhost
    @manifest.passenger_configure_gem_path
    @manifest.passenger_site
    assert_not_nil @manifest.puppet_resources[Puppet::Type::File]["/etc/apache2/sites-available/#{@manifest.configatron.application}"]
    assert_match /RailsAllowModRewrite On/, @manifest.puppet_resources[Puppet::Type::File]["/etc/apache2/sites-available/#{@manifest.configatron.application}"].params[:content].value
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Exec].find { |n, r| r.params[:command].value == '/usr/sbin/a2dissite 000-default' }
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Exec].find { |n, r| r.params[:command].value == "/usr/sbin/a2ensite #{@manifest.configatron.application}" }
  end

  def test_passenger_vhost_configuration
    @manifest.passenger_configure_gem_path
    @manifest.configure(:passenger => { :rails_base_uri => '/test' })
    @manifest.passenger_site
    assert_match /RailsBaseURI \/test/, @manifest.puppet_resources[Puppet::Type::File]["/etc/apache2/sites-available/#{@manifest.configatron.application}"].params[:content].value
  end

  def test_ssl_vhost_configuration
    @manifest.passenger_configure_gem_path
    @manifest.configure(:ssl => {
      :certificate_file => 'cert_file',
      :certificate_key_file => 'cert_key_file',
      :certificate_chain_file => 'cert_chain_file'
    })
    @manifest.passenger_site
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Exec].find { |n, r| r.params[:command].value == '/usr/sbin/a2enmod ssl' }
    assert_match /SSLEngine on/, @manifest.puppet_resources[Puppet::Type::File]["/etc/apache2/sites-available/#{@manifest.configatron.application}"].params[:content].value
    assert_match /https/, @manifest.puppet_resources[Puppet::Type::File]["/etc/apache2/sites-available/#{@manifest.configatron.application}"].params[:content].value
  end

  def test_installs_postfix
    @manifest.postfix
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Package]["postfix"]
  end

  def test_installs_ntp
    @manifest.ntp
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Service]["ntp"]
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Package]["ntp"]
  end

  def test_installs_cron
    @manifest.cron_packages
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Service]["cron"]
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Package]["cron"]
  end

  def test_sets_default_time_zone
    @manifest.time_zone
    assert_not_nil @manifest.puppet_resources[Puppet::Type::File]["/etc/timezone"]
    assert_not_nil @manifest.puppet_resources[Puppet::Type::Package]["/etc/localtime"]
    assert_equal '/usr/share/zoneinfo/UTC', @manifest.puppet_resources[Puppet::Type::File]["/etc/localtime"].params[:ensure].value
    assert_equal "UTC\n", @manifest.puppet_resources[Puppet::Type::File]["/etc/timezone"].params[:content].value
  end

  def test_sets_default_time_zone
    @manifest.configatron.remove('time_zone')
    @manifest.time_zone
    assert_not_nil @manifest.puppet_resources[Puppet::Type::File]["/etc/timezone"]
    assert_equal "UTC\n", @manifest.puppet_resources[Puppet::Type::File]["/etc/timezone"].params[:content].value
    assert_not_nil @manifest.puppet_resources[Puppet::Type::File]["/etc/localtime"]
    assert_equal '/usr/share/zoneinfo/UTC', @manifest.puppet_resources[Puppet::Type::File]["/etc/localtime"].params[:ensure].value
  end

  def test_sets_configured_time_zone
    @manifest.configure(:time_zone => 'America/New_York')
    @manifest.time_zone
    assert_not_nil @manifest.puppet_resources[Puppet::Type::File]["/etc/timezone"]
    assert_equal "America/New_York\n", @manifest.puppet_resources[Puppet::Type::File]["/etc/timezone"].params[:content].value
    assert_not_nil @manifest.puppet_resources[Puppet::Type::File]["/etc/localtime"]
    assert_equal '/usr/share/zoneinfo/America/New_York', @manifest.puppet_resources[Puppet::Type::File]["/etc/localtime"].params[:ensure].value
  end

end