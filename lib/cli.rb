require 'pp'
require 'json'
require 'yaml'
require 'emoji'
require 'colorize'
require 'test/unit'
extend Test::Unit::Assertions


# Helpers

def parse_specs(path)

  # Specs
  specmap = {}
  for path in Dir.glob("#{path}/**/*.yml")
    spec = parse_spec(File.read(path))
    if !spec
      next
    elsif !specmap.include?(spec['package'])
      specmap[spec['package']] = spec
    else
      specmap[spec['package']]['features'].merge!(spec['features'])
      specmap[spec['package']]['scope'].merge!(spec['scope'])
    end
  end

  # Hooks
  # TODO: implement

  # Result
  specs = Array(specmap.sort.to_h.each_value)

  return specs

end


def parse_spec(spec)

  # Package
  contents = YAML.load(spec)
  begin
    feature = parse_feature(contents[0])
    package = feature['result']
    assert_equal(feature['assign'], 'PACKAGE')
    assert_equal(feature['skip'], nil)
    if package.is_a?(String)
      package = {'default' => [package]}
    elsif package.is_a?(Array)
      package = {'default' => package}
    elsif package.is_a?(Hash)
      for key, value in package.each_pair()
        package[key] = value.is_a?(Array) ? value : [value]
      end
    end
  rescue Exception
    return nil
  end

  # Features
  features = []
  for feature in contents
    feature = parse_feature(feature)
    features.push(feature)
  end

  # Scope
  scope = {}
  packages = []
  attributes = {}
  for namespace, module_names in package.each_pair
    packages.push(*module_names)
    namespace_scope = scope
    if namespace != 'default'
      if !scope.key?(namespace) then scope[namespace] = {} end
      namespace_scope = scope[namespace]
    end
    for module_name in module_names
      attributes = get_module_attributes(module_name)
      namespace_scope.merge!(attributes)
      if !attributes.empty?
        break
      end
    end
    if attributes.empty?
      scope = {}
      break
    end
  end
  package = packages.sort().join('/')

  return {
    'package' => package,
    'features' => features,
    'scope' => scope,
  }

end


def parse_feature(feature)
  if feature.is_a?(String)
    return {'comment' => feature}
  end
  left, right = Array(feature.each_pair)[0]

  # Left side
  call = false
  match = /^(?:(.*):)?(?:([^=]*)=)?([^=].*)?$/.match(left)
  skip, assign, property = match[1], match[2], match[3]
  if !!skip
    filters = skip.split(':')
    skip = (filters[0] == 'not') == (filters.include?('rb'))
  end
  if !assign and !property
    raise Exception.new('Non-valid feature')
  end
  if !!property
    call = true
    if property.end_with?('==')
      property = property[0..-3]
      call = false
    end
  end

  # Right side
  args = []
  kwargs = {}
  result = right
  if !!call
    result = nil
    for item in right
      if item.is_a?(Hash) && item.length == 1
        item_left, item_right = Array(item.each_pair)[0]
        if item_left == '=='
          result = item_right
          next
        end
        if item_left.end_with?('=')
          kwargs[item_left[0..-2]] = item_right
          next
        end
      end
      args.push(item)
    end
  end

  # Text repr
  text = property
  if !!assign
    text = "#{assign} = #{property || JSON.generate(result)}"
  end
  if !!call
    items = []
    for item in args
      items.push(JSON.generate(item))
    end
    for name, item in kwargs.each_pair
      items.push("#{name}=#{JSON.generate(item)}")
    end
    text = "#{text}(#{items.join(', ')})"
  end
  if !!result && !assign
    text = "#{text} == #{result == 'ERROR' ? result : JSON.generate(result)}"
  end
  text = text.gsub(/{"([^{}]*?)": null}/, '\1')

  return {
    'comment' => nil,
    'skip' => skip,
    'call' => call,
    'assign' => assign,
    'property' => property,
    'args' => args,
    'kwargs' => kwargs,
    'result' => result,
    'text' => text,
  }

end


def test_specs(specs)
  success = true
  message = "\n #  Ruby\n".bold
  puts(message)
  for spec in specs
    spec_success = test_spec(spec)
    success = success && spec_success
  end
  return success
end


def test_spec(spec)
  passed = 0
  amount = spec['features'].length
  message = Emoji.find_by_alias('heavy_minus_sign').raw * 3 + "\n\n"
  puts(message)
  for feature in spec['features']
    result = test_feature(feature, spec['scope'])
    if result
      passed += 1
    end
  end
  success = (passed == amount)
  color = 'green'
  message = ("\n " + Emoji.find_by_alias('heavy_check_mark').raw + '  ').green.bold
  if !success
    color = 'red'
    message = ("\n " + Emoji.find_by_alias('x').raw + '  ').red.bold
  end
  message += "#{spec['package']}: #{passed}/#{amount}\n".colorize(color).bold
  puts(message)
  return success
end


def test_feature(feature, scope)

  # Comment
  if !!feature['comment']
    message = "\n # #{feature['comment']}\n".bold
    puts(message)
    return true
  end

  # Skip
  if !!feature['skip']
    message = " #{Emoji.find_by_alias('heavy_minus_sign').raw}  ".yellow
    message += feature['text']
    puts(message)
    return true
  end

  # Dereference
  #TODO: deepcopy feature
  if !!feature['call']
    feature['args'] = dereference_value(feature['args'], scope)
    feature['kwargs'] = dereference_value(feature['kwargs'], scope)
  end
  feature['result'] = dereference_value(feature['result'], scope)

  # Execute
  result = feature['result']
  if !!feature['property']
    begin
      property = scope
      for name in feature['property'].split('.')
        property = get_property(property, name)
      end
      if !!feature['call']
        # TODO: support kwargs
        if property.respond_to?('new')
          result = property.new(*feature['args'])
        else
          result = property.call(*feature['args'])
        end
      else
        result = property
      end
    rescue Exception
      result = 'ERROR'
    end
  end

  # Assign
  if !!feature['assign']
    owner = scope
    names = feature['assign'].split('.')
    for name in names[0..-2]
      owner = get_property(owner, name)
    end
    # TODO: ensure constants are immutable
    set_property(owner, names[-1], result)
  end

  # Compare
  # TODO: isoformat value
  if feature['result'] != nil
    success = result == feature['result']
  else
    success = result != 'ERROR'
  end
  if success
    message = " #{Emoji.find_by_alias('heavy_check_mark').raw}  ".green
    message += feature['text']
    puts(message)
  else
    begin
      result_text = JSON.generate(result)
    rescue Exception
      result_text = result.to_s
    end
    message = " #{Emoji.find_by_alias('x').raw}  ".red
    message += "#{feature['text']} # #{result_text}"
    puts(message)
  end

  return success

end


def get_module_attributes(module_name)
  attributes = {}
  begin
    require(module_name)
  rescue Exception
    return {}
  end
  for item in ObjectSpace.each_object
    if module_name == String(item).downcase
      begin
        module_scope = Kernel.const_get(item)
      rescue Exception
        next
      end
      for name in module_scope.constants
        attributes[String(name)] = module_scope.const_get(name)
      end
    end
  end
  return attributes
end


def dereference_value(value, scope)
  #TODO: deepcopy value
  if value.is_a?(Hash) && value.length == 1 && Array(value.each_value)[0] == nil
    result = scope
    for name in Array(value.each_key)[0].split('.')
      result = get_property(result, name)
    end
    value = result
  elsif value.is_a?(Hash)
    for key, item in value
      value[key] = dereference_value(item, scope)
    end
  elsif value.is_a?(Array)
    for item, index in value.each_with_index
      value[index] = dereference_value(item, scope)
    end
  end
  return value
end


def get_property(owner, name)
  if owner.class == Hash
    return owner[name]
  elsif owner.class == Array
    return owner[name.to_i]
  end
  return owner.method(name)
end


def set_property(owner, name, value)
  if owner.class == Hash
    owner[name] = value
    return
  elsif owner.class == Array
    owner[name.to_i] = value
    return
  end
  return owner.const_set(name, value)
end


# Main program

path = ARGV[0] || '.'
specs = parse_specs(path)
success = test_specs(specs)
if !success
  exit(1)
end
