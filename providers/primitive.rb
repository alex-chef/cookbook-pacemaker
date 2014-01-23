# Author:: Robert Choi
# Cookbook Name:: pacemaker
# Provider:: primitive
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

require ::File.join(::File.dirname(__FILE__), *%w(.. libraries cib_objects))

include Chef::Libraries::Pacemaker::CIBObjects

# For vagrant env, switch to the following 'require' command.
#require "/srv/chef/file_store/cookbooks/pacemaker/providers/helper"

action :create do
  name = new_resource.name

  if @current_resource_definition.nil?
    create_resource(name)
  else
    if @current_resource.agent != new_resource.agent
      raise "Existing primitive '#{name}' has agent but recipe wanted #{new_resource.agent}"
    end

    modify_resource(name)
  end
end

action :delete do
  name = new_resource.name
  cmd = "crm resource stop #{name}; crm configure delete #{name}"

  e = execute "delete primitive #{name}" do
    command cmd
    only_if { cib_object_exists?(name) }
  end

  new_resource.updated_by_last_action(true)
  Chef::Log.info "Deleted primitive '#{name}'."
end

action :start do
  name = new_resource.name
  raise "no such resource #{name}" unless cib_object_exists?(name)
  next if resource_running?(name)
  shell_out! %w(crm resource start) + [name]
  Chef::Log.info "Successfully started primitive '#{name}'."
end

action :stop do
  name = new_resource.name
  raise "no such resource #{name}" unless cib_object_exists?(name)
  next unless resource_running?(name)
  shell_out! %w(crm resource stop) + [name]
  Chef::Log.info "Successfully stopped primitive '#{name}'."
end

# Instantiate @current_resource and read details about the existing
# primitive (if any) via "crm configure show" into it, so that we
# can compare it against the resource requested by the recipe, and
# create / delete / modify as necessary.

# http://docs.opscode.com/lwrp_custom_provider_ruby.html#load-current-resource
def load_current_resource
  name = @new_resource.name

  obj_definition = get_cib_object_definition(name)
  return unless obj_definition

  if obj_definition.empty? # probably overly paranoid
    raise "CIB object '#{name}' existed but definition was empty?!"
  end

  unless obj_definition =~ /\Aprimitive #{name} (\S+)/
    Chef::Log.warn "Resource '#{name}' was not a primitive"
    return
  end
  agent = $1

  @current_resource_definition = obj_definition
  @current_resource = Chef::Resource::PacemakerPrimitive.new(name)
  @current_resource.agent(agent)

  %w(params meta).each do |data_type|
    h = extract_hash(name, obj_definition, data_type)
    @current_resource.send(data_type.to_sym, h)
  end
end

def create_resource(name)
  cmd = "crm configure primitive #{name} #{new_resource.agent}"
  cmd << resource_params_string(new_resource.params)
  cmd << resource_meta_string(new_resource.meta)
  cmd << resource_op_string(new_resource.op)

  Chef::Log.debug "creating new primitive #{name} via #{cmd}"

  execute cmd do
    action :nothing
  end.run_action(:run)

  if cib_object_exists?(name)
    new_resource.updated_by_last_action(true)
    Chef::Log.info "Successfully configured primitive '#{name}'."
  else
    Chef::Log.error "Failed to configure primitive #{name}."
  end
end

def modify_resource(name)
  configure_cmd_prefix = "crm_resource --resource keystone"

  cmds = []
  new_resource.params.each do |k, v|
    if @current_resource.params[k] == v
      Chef::Log.debug("#{name}'s #{k} param didn't change")
    else
      Chef::Log.info("#{name}'s #{k} param changed to #{v}")
      cmds << configure_cmd_prefix + " --set-parameter #{k} --parameter-value #{v}"
    end
  end

  cmds.each do |cmd|
    converge_by("execute #{cmd}") do
      result = shell_out!(cmd)
      Chef::Log.info("#{cmd} ran successfully")
    end
  end

  new_resource.updated_by_last_action(true) unless cmds.empty?
end
