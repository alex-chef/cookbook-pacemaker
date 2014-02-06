# Author:: Robert Choi
# Cookbook Name:: pacemaker
# Provider:: 
#
# Copyright:: 2013, Robert Choi
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require ::File.expand_path('../libraries/pacemaker/cib_object',
                           ::File.dirname(__FILE__))

action :create do
  name = new_resource.name
  rsc = new_resource.rsc

  unless resource_exists?(name)
    cmd = "crm configure ms #{name} #{rsc}"

    if new_resource.meta
      cmd << " meta"
      new_resource.meta.each do |key, value|
        cmd << " #{key}=\"#{value}\""
      end
    end

    cmd_ = Mixlib::ShellOut.new(cmd)
    cmd_.environment['HOME'] = ENV.fetch('HOME', '/root')
    cmd_.run_command
    begin
      cmd_.error!
      if resource_exists?(name)
        new_resource.updated_by_last_action(true)
        Chef::Log.info "Successfully configured ms '#{name}'."
      else
        Chef::Log.error "Failed to configure ms #{name}."
      end
    rescue
      Chef::Log.error "Failed to configure ms #{name}."
    end
  end
end

action :delete do
  name = new_resource.name
  cmd = "crm resource stop #{name}; crm configure delete #{name}"

    e = execute "delete ms #{name}" do
      command cmd
      only_if { resource_exists?(name) }
    end

    new_resource.updated_by_last_action(true)
    Chef::Log.info "Deleted ms '#{name}'."
end
