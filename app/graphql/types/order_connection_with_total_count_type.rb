class Types::OrderEdgeType < GraphQL::Types::Relay::BaseEdge
  node_type(Types::OrderType)
end

class Types::OrderConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
  edge_type(Types::OrderEdgeType)

  field :total_count, Integer, null: false
  def total_count
    # - `object` is the Connection
    # - `object.nodes` is the collection of Orders
    object.nodes.size
  end
end
