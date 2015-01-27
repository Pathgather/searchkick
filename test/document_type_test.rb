require_relative "test_helper"

class DocumentTypeTest < Minitest::Test

  def test_default_document_type
    index = Searchkick::Index.new('dummy')
    assert_equal 'product', index.klass_document_type(Product)
  end

  def test_custom_document_type
    begin
      Part.instance_eval { def document_type; 'partz'; end }

      index = Searchkick::Index.new('dummy')
      assert_equal 'partz', index.klass_document_type(Part)
    ensure
      Part.instance_eval { undef :document_type }
    end
  end

end
