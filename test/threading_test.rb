require File.join(File.dirname(__FILE__), 'test_helper')

class ThreadingTest < Test::Unit::TestCase
  
  
  ########### helper methods: begin
    
  def path_helper(file)
    File.dirname(__FILE__) + file
  end
  
  # create message hash of yaml file
  # hash key is message_id
  # hash value the message with subject, message and references attributes
  def self.parse_inbox(path)
    yaml = File.open(path) {|f| YAML.load(f)}

    messages = Hash.new
    yaml.each do |key, value|
      ref = value["references"]
      if !ref 
        ref = []
      end   
    m = MailHelper::Message.new(value["subject"], key, ref)
    messages[key] = m
  end

  messages
  end
  
  def parse_messages(file)
    messages = parse_inbox path_helper("/#{file}")
  end
  
  def message(subject, message_id, references)
    MailHelper::Message.new(subject, message_id, references)
  end
  
  def empty_container()
    MailHelper::Container.new
  end
  
  def container(subject, message_id, references)
    MailHelper::Container.new message(subject, message_id, references)
  end
  
  ########### helper methods: end
  
  def setup
    @thread = MailHelper::Threading.new
    # change log level
    log = Logging::Logger['Threading']
    log.level = :info
      
    @debug = MailHelper::Debug.new
    @message_parser = MailHelper::MessageParser.new
  end
  
  test" should create valid message by using references field" do
    message = MailHelper::MessageFactory.create("subject", "message_id", ["a"], ["a", "c"])
    assert_equal ["a", "c"], message.references
  end
  
  test" should create valid message by using in-reply-to field" do
    message = MailHelper::MessageFactory.create("subject", "message_id", ["a"], nil)
    assert_equal ["a"], message.references
  end
  
  test" should create valid message by using in-reply-to field with multiple message-IDs" +
  " but taking only the first message-ID into account" do
    message = MailHelper::MessageFactory.create("subject", "message_id", ["a", "c"], nil)
    assert_equal ["a"], message.references
  end
  
  #
  # a
  # +- b
  #    +- c
  #       +- d
  #          +- e
  # b
  # +- c
  #    +- d
  #       +- e
  # c
  # +- d
  #    +- e
  # d
  # +- e
  # e
  #
  test" should create id_table for each message" do
    messages = [
      message("subject", "a", ""),
      message("subject", "b", "a"),
      message("subject", "c", ["a", "b"]),
      message("subject", "d", ["a", "b", "c"]),
      message("subject", "e", "d")
    ]
    
    # calling private method here 
    id_table = @thread.send(:create_id_table, messages)
        
    assert_equal 5, id_table.size
    assert_equal "b", child_message_id(id_table, "a", 0)
    assert_equal "c", child_message_id(id_table, "b", 0)
    assert_equal "d", child_message_id(id_table, "c", 0)
    assert_equal "e", child_message_id(id_table, "d", 0)
    assert_equal 0, child_count(id_table, "e")
  end
    
  def child_count(id_table, id)
    id_table[id].children.size
  end
  
  def child_message_id(id_table, id, child_index)
    child(id_table, id, child_index).message.message_id
  end
  
  def child(id_table, id, child_index)
    id_table[id].children[child_index]
  end
  #
  # a
  # +- b
  #    +- c (dummy) 
  #       +- d
  #         +- e
  # b
  # +- c (dummy)
  #    +- d
  #       +- e
  # c (dummy)
  # +- e
  #    +- e
  # d
  # +- e
  # e:subject
  #
  test" should create id_table for each message and dummy containers in case of"+
  " reference to non-existent message" do
    messages = []
    messages << message("subject", "a", "")
    messages << message("subject", "b", "a")
    # message "c" is the dummy
    messages << message("subject", "d", ["a", "b", "c"])
    messages << message("subject", "e", "d")
 
    # calling private method here
    id_table = @thread.send(:create_id_table, messages)
    
    id_table.should have(5).items
    id_table["a"].children.should have(1).item
    id_table["a"].children[0].message.message_id == "b"
    
    # dummy "c" checked
    id_table["b"].children.should have(1).items
    id_table["b"].children[0].message.should be_nil

    id_table["c"].children.should have(1).item
    id_table["c"].children[0].message.message_id == "d"
    
    id_table["d"].children.should have(1).item
    id_table["d"].children[0].message.message_id == "e"
    
    id_table["e"].children.should be_empty  
  end
  
  #
  # a
  # +- b
  #    +- c (dummy)
  #       +- d
  #          +- e
  # b 
  # +- c
  #    +- d
  #       +- e
  # y (dummy)
  # c
  # +- d
  #    +- e
  # z  (dummy)
  # +- y (dummy)
  # d
  # +- e
  # e
  #  
  test" should create id_table for each message and nested dummy containers in case of"+
  " references to non-existent messages" do
    messages = []
    messages << message("subject", "a", "")
    messages << message("subject", "b", "a")
    # message "c" is the dummy
    messages << message("subject", "d", ["a", "b", "c"])
    # message "y" and "z" is a dummy
    messages << message("subject", "e", ["z", "y", "d"])
 
    # calling private method here
    id_table = @thread.send(:create_id_table, messages)
 
    id_table.should have(7).items
    id_table["a"].children.should have(1).item
    id_table["a"].children[0].message.message_id == "b"
    
    # dummy "c" checked
    id_table["b"].children.should have(1).items
    id_table["b"].children[0].should be_dummy

    id_table["c"].should be_dummy
    id_table["c"].children.should have(1).item
    id_table["c"].children[0].message.message_id == "d"
    
    id_table["z"].children.should have(1).item
    id_table["z"].children[0].should be_dummy
    
    id_table["y"].children.should be_empty
    
    id_table["d"].children.should have(1).item
    id_table["d"].children[0].message.message_id == "e"
    
    id_table["e"].children.should be_empty  
  end
  
  #
  # before: 
  # a
  # +- b
  #   +- dummy 
  #  
  # after:
  # a
  # +- b
  # 
  test" should prune containers with empty message and no children" do  
    root = empty_container
    container_a = container("subject", "a", [])
    root.add_child container_a
    container_b = container("subject", "b", "a")
    container_a.add_child container_b
    # dummy container
    container_z = empty_container
    container_b.add_child(container_z)
    
    # calling private method here
    @thread.send(:prune_empty_containers, root)
    
    root.children.should have(1).item
    root.children[0].should == container_a
    container_a.children.should have(1).item
    container_a.children[0].should == container_b
    container_b.children.should be_empty
  end
  
  # 
  # before: 
  # a
  # +- b
  #    +- z (dummy)
  #       +- c
  #
  # after:
  # a
  # +- b
  #    +- c
  #  
  test" should prune containers with empty message and 1 non-empty child" do 
    root = empty_container
    container_a = container("subject", "a", [])
    root.add_child container_a
    container_b = container("subject", "b", "a")
    container_a.add_child container_b
    container_c = container("subject", "c", ["a", "z"])
    # dummy container
    container_z = empty_container
    container_b.add_child container_z
    container_z.add_child container_c
    
    # calling private method here
    @thread.send(:prune_empty_containers, root)
    
    root.children.should have(1).items
    root.children[0].should == container_a
    container_a.children[0] == container_b
    container_b.children[0].children[0] == container_c
  end
  
  #
  # before:
  # a
  # z (dummy)
  # +- c
  #
  # after:
  # a
  # b
  #
  #
  test" should promote child of containers with empty message and 1 child directly to root level" do 
    root = empty_container
    
    container_a = container("subject", "a", [])
    root.add_child(container_a)
    container_b = container("subject", "b", ["z"])
    # dummy container
    container_z = empty_container
    root.add_child(container_z)
    container_z.add_child(container_b)
    
    # calling private method here
    @thread.send(:prune_empty_containers, root)
    
    root.children.should have(2).items
    root.children[0].should == container_a
    root.children[1].should == container_b
  end
  
  #
  # before:
  # a
  # z (dummy)
  # +- b
  # +- c
  #
  # after:
  # a
  # z (dummy)
  # +- b
  # +- c
  # 
  test" should do *not* promote children of containers with empty message and 2 children directly to root level" do 
    root = empty_container
    container_a = container("subject", "a", [])
    root.add_child container_a
    # dummy container
    container_z = empty_container
    root.add_child container_z
    # dummy container children
    container_b = container("subject", "b", ["a", "z"])
    container_z.add_child container_b
    container_c = container("subject", "c", ["a", "z"])
    container_z.add_child container_c
    
    # calling private method here
    @thread.send(:prune_empty_containers, root)
    
    root.children.should have(2).items
    root.children[0].should == container_a
    root.children[1].should be_dummy
    container_z.children.should have(2).items
    container_z.children[0].should == container_b
    container_z.children[1].should == container_c
  end
  
  
  #
  # before:
  # a
  # z (dummy)
  # +- y (dummy)
  #    +- b
  #    +- c
  #    +- d
  #
  # after:
  # a
  # z (dummy)
  # +- b 
  # +- c
  # +- d
  # 
  test" should promote children of containers with empty message and 2 children directly to next level" do 
    root = empty_container
    container_a = container("subject", "a", [])
    root.add_child container_a
    # dummy container
    container_z = empty_container
    root.add_child container_z
    # 2nd dummy container
    container_y = empty_container
    container_z.add_child container_y
    # dummy container children
    container_b = container("subject", "b", ["a", "z"])
    container_y.add_child container_b
    container_c = container("subject", "c", ["a", "z"])
    container_y.add_child container_c
    container_d = container("subject", "d", ["a", "z"])
    container_y.add_child container_d
    
    # calling private method here
    @thread.send(:prune_empty_containers, root)
    
    root.children.should have(2).items
    root.children[0].should == container_a
    root.children[1].should be_dummy
    root.children[1].children.should have(3).items
    root.children[1].children[0].should == container_d
    root.children[1].children[1].should == container_c
    root.children[1].children[2].should == container_b
  end
  
  
  #
  # before:
  # a
  # z (dummy)
  # +- y (dummy)
  #    +- x (dummy)
  #       +- b
  #       +- c
  # +- d
  #
  # after:
  # a
  # z (dummy)
  # +- b
  # +- c
  # +- d
  # 
  test" should promote children of several containers with empty message and 2 children directly to next level" do 
    root = empty_container
    container_a = container("subject", "a", [])
    root.add_child container_a
    # dummy container
    container_z = empty_container
    root.add_child container_z
    # 2nd dummy container
    container_y = empty_container
    container_z.add_child container_y
    # 3nd dummy container
    container_x = empty_container
    container_y.add_child container_x
    # dummy container children
    container_b = container("subject", "b", ["a", "z"])
    container_x.add_child container_b
    container_c = container("subject", "c", ["a", "z"])
    container_x.add_child container_c
    container_d = container("subject", "d", ["a", "z"])
    container_z.add_child container_d
    
    # calling private method here
    @thread.send(:prune_empty_containers, root)
    
    root.children.should have(2).items
    root.children[0].should == container_a
    root.children[1].should be_dummy
    container_z.children.should have(3).items
    container_z.children[0].should == container_d
    container_z.children[1].should == container_b
    container_z.children[2].should == container_c
  end
  
  #
  # before:
  # z (dummy)
  # +- y (dummy)
  #    +- a
  # +- x (dummy)
  #
  # after:
  # a
  #
  test" should promote children of several containers with empty message and multiple children" do 
    root = empty_container
    container_z = empty_container
    root.add_child(container_z)
    container_y = empty_container
    container_z.add_child container_y
    container_a = container("subject", "a", [])
    container_y.add_child container_a
    container_x = empty_container
    container_z.add_child container_x
      
    # calling private methodhere
    @thread.send(:prune_empty_containers, root)
    
    root.children.should have(1).item
    root.children[0].should == container_a
    container_a.children.should be_empty
  end
  
  #
  # before:
  # z (dummy)
  # +- y (dummy)
  #    +- x (dummy)
  #       +- w (dummy)
  #          +- a
  #             +- b
  #          +- c
  #             +- d
  # +- v
  #
  # after:
  # z (dummy)
  # +- a
  #    +- b
  # +- c
  #    +- d
  #  
  test" should promote children of several containers with empty message and multiple children 2" do 
    
    root = empty_container
    container_z = empty_container
    root.add_child(container_z)
    container_y = empty_container
    container_z.add_child container_y
    container_x = empty_container
    container_y.add_child container_x
    container_w = empty_container
    container_x.add_child container_w
    container_a = container("subject", "a", [])
    container_w.add_child container_a
    container_b = container("subject", "b", [])
    container_a.add_child container_b
    container_c = container("subject","c", [])
    container_w.add_child container_c
    container_d = container("subject", "d", [])
    container_c.add_child container_d
    container_v = empty_container
    container_z.add_child container_v
    
    # calling private method here
    @thread.send(:prune_empty_containers, root)

    root.children.should have(1).item
    root.children[0].should == container_z
    container_z.children.should have(2).items
    container_z.children[0].should == container_c
    container_z.children[1].should == container_a
    container_a.children[0].should == container_b
    container_c.children[0].should == container_d
  end
  

  #
  # before:
  # z (dummy)
  # +- y (dummy)
  #    +- x (dummy)
  #       +- w (dummy)
  #          +- a
  #             +- b 
  #          +- c   
  #             +- d
  #    +- v
  #       +- u
  #          +- t  
  #             +- s
  #                +- q  
  #                   +- e
  #          +- p
  #             +- f
  #
  # after:
  # z (dummy) 
  # +- a
  #    +- b
  # +- c
  #    +- d
  # +- e
  # +- f
  # 
  test" should promote children of several containers with empty message and multiple children 3" do 
    root = empty_container
    container_z = empty_container
    root.add_child(container_z)
    container_y = empty_container
    container_z.add_child container_y
    container_x = empty_container
    container_y.add_child container_x
    container_w = empty_container
    container_x.add_child container_w
    container_a = container("subject", "a", [])
    container_w.add_child container_a
    container_b = container("subject", "b", [])
    container_a.add_child container_b
    container_c = container("subject","c", [])
    container_w.add_child container_c
    container_d = container("subject", "d", [])
    container_c.add_child container_d
    container_v = empty_container
    container_z.add_child container_v
    container_u = empty_container
    container_v.add_child container_u
    container_t = empty_container
    container_u.add_child container_t
    container_s = empty_container
    container_t.add_child container_s
    container_q = empty_container
    container_t.add_child container_q
    container_e = container("subject", "e", [])
    container_q.add_child container_e
    container_p = empty_container
    container_u.add_child container_p
    container_f = container("subject", "f", [])
    container_p.add_child container_f
    
    # calling private method here
    @thread.send(:prune_empty_containers, root)
    
    root.children.should have(1).item
    root.children[0].should == container_z
    container_z.children.should have(4).items
    container_z.children[0].should == container_f
    container_z.children[1].should == container_e
    container_z.children[2].should == container_c
    container_z.children[3].should == container_a
    
    container_a.children[0].should == container_b
    container_c.children[0].should == container_d
  end
  
  #
  # before:
  # Subject A
  # Subject Z
  # Re: Subject Z
  # Re: Subject Z
  #
  # after:
  # Subject A
  # Subject Z
  #   +- Re: Subject Z
  #   +- Re: Subject Z
  #
  test" should group all messages in the root set by subject" do
    root = empty_container
    container_a = container("subject_a", "a", [])
    root.add_child container_a
    container_b = container("Re: subject_z", "b", [])
    root.add_child container_b
    container_c = container("Re: subject_z", "c", [])
    root.add_child container_c
    container_d = container("subject_z", "d", [])
    root.add_child container_d

    # calling private method here
    subject_hash = @thread.send(:group_root_set_by_subject, root)
    
    subject_hash.key?("subject_a").should == true
    subject_hash.key?("subject_z").should == true
    
    root.children.should have(2).items
    root.children[0].should == container_a
    root.children[1].should == container_d
    container_d.children.should have(2).items
    container_d.children[0].should == container_c
    container_d.children[1].should == container_b
  end
 
  #
  # before:
  # Subject A
  # Subject Z
  # Re: Subject Z
  # Re: Re: Subject Z
  #
  # after:
  # Subject A
  # Subject Z
  #   +- Re: Subject Z
  #      +- Re: Re: Subject Z
  #
  test" should group all messages in the root set by subject including"+
   "multiple nested messages" do
    root = empty_container
    container_a = container("subject_a", "a", [])
    root.add_child container_a
    container_b = container("Re: subject_z", "b", [])
    root.add_child container_b
    container_c = container("Re: subject_z", "c", [])
    root.add_child container_c
    container_d = container("subject_z", "d", [])
    root.add_child container_d

    #@debug.print_tree(root)        
    # calling private method here
    subject_hash = @thread.send(:group_root_set_by_subject, root)
    #@debug.print_subject_hash(subject_hash)
    #@debug.print_tree(root)
    
    subject_hash.key?("subject_a").should == true
    subject_hash.key?("subject_z").should == true
    
    root.children.should have(2).items
    root.children[0].should == container_a
    root.children[1].should == container_d
    container_d.children.should have(2).items
    container_d.children[0].should == container_c
    container_d.children[1].should == container_b
  end

  test" should create tree based on message-IDs and references" do    
    messages = []
    messages << message("subject", "a", "")
    messages << message("subject", "b", "a")
    messages << message("subject", "c", ["a", "b"])
    messages << message("subject", "d", ["a", "b", "c"])
    messages << message("subject", "e", "d")
    
    root = @thread.thread(messages)
    
    root.children.should have(1).items
    root.children[0].message.message_id == "a"
    root.children[0].children[0].message.message_id == "b"
    root.children[0].children[0].children[0].message.message_id == "c"
    root.children[0].children[0].children[0].children[0].message.message_id == "d"
    root.children[0].children[0].children[0].children[0].children[0].message.message_id == "e"
  end
  
  # test" should create tree based on message-IDs and references and on Subject" do    
  #     messages = Hash.new
  #     messages["a"] = message("subject", "a", "")
  #     messages["b"] = message("subject", "b", "a")
  #     messages["c"] = message("subject", "c", ["a", "b"])
  #     messages["d"] = message("subject", "d", ["a", "b", "c"])
  #     messages["e"] = message("subject", "e", "d")
  #     messages["f"] = message("Hello", "f", "")
  #     messages["g"] = message("Re:Hello", "g", "")
  #     messages["h"] = message("Re:Hello", "h", "")            
  #     messages["i"] = message("Fwd:Hello", "i", "")
  #     messages["j"] = message("Re:Re: Hello", "j", "")            
  #     
  #     root = @thread.thread(messages)
  #     #subject_hash = @thread.group_root_set_by_subject(root)  
  #     #@debug.print_subject_hash subject_hash
  #     @debug.print_tree(root)
  #     
  #     root.children.should have(2).items
  #     root.children[0].message.message_id == "a"
  #     root.children[0].children[0].message.message_id == "b"
  #     root.children[0].children[0].children[0].message.message_id == "c"
  #     root.children[0].children[0].children[0].children[0].message.message_id == "d"
  #     root.children[0].children[0].children[0].children[0].children[0].message.message_id == "e"
  #     
  #     root.children[1].message.message_id == "f"
  #     root.children[1].children[0].message.message_id == "j"
  #     root.children[1].children[1].message.message_id == "i"
  #     root.children[1].children[2].message.message_id == "h"
  #     root.children[1].children[3].message.message_id == "g"
  #   end
  #   
  
end