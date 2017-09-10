require "spec_helper"


# Tests

RSpec.describe "cli" do

  it "works with packspec" do
    specs = parse_specs('spec/packspec.yml')
    valid = test_specs(specs)
    expect(valid).to be true
  end

  it "works with packspec assertion fail" do
    specs = parse_specs('spec/packspec.yml')
    specs[0]['features'] = specs[0]['features'].take(3)
    specs[0]['features'][2]['result'] = 'FAIL'
    valid = test_specs(specs)
    expect(valid).to be false
  end

  it "works with packspec exception fail" do
    specs = parse_specs('spec/packspec.yml')
    specs[0]['features'] = specs[0]['features'].take(3)
    specs[0]['features'][2]['call'] = true
    valid = test_specs(specs)
    expect(valid).to be false
  end

end
