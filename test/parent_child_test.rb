require_relative "test_helper"

class TestParentChild < Minitest::Unit::TestCase
  def setup
    super

    store [
      {id: 1, name: "Product1", orders_count: 4},
      {id: 2, name: "Product2", orders_count: 5}
    ]

    store [
      {product_id: 1, name: "P1-1", total: 6},
      {product_id: 1, name: "P1-2", total: 7},
      {product_id: 2, name: "P2-1", total: 8},
      {product_id: 2, name: "P2-2", total: 9}
    ], Part
  end

  def test_type_search
    results = Product.search('*').to_a
    assert_equal 2, results.length
    results.each do |result|
      assert_equal Product, result.class
    end

    results = Part.search('*').to_a
    assert_equal 4, results.length
    results.each do |result|
      assert_equal Part, result.class
    end
  end

  def test_child_search
    assert_equal ["Product1"], Product.search('*', has_child: {type: 'part', where: {total: 6}}).map(&:name)
  end

  def test_parent_search
    assert_equal ["P1-1", "P1-2"], Part.search('*', has_parent: {type: 'product', where: {orders_count: 4}}).map(&:name).sort
  end

  def test_parent_reindex
    # Make sure the reindex hack in test_helper is actually functional.
    # Also tests that _parent is set appropriately on bulk imports.
    Product.reindex

    # Hacky. Need to wait for reindex to take effect.
    t = Time.now
    loop do
      if ["P1-1", "P1-2"] == Part.search('*', has_parent: {type: 'product', where: {orders_count: 4}}).map(&:name).sort
        break
      elsif Time.now < (t + 5)
        sleep 0.1
      else
        raise "Never happened!"
      end
    end
  end

  def test_child_reindex
    assert_raises RuntimeError, "Don't reindex a searchkick child!" do
      Part.reindex
    end
  end
end
