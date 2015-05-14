db = require "lapis.db.mysql"

import setup_db, teardown_db from require "spec_mysql.helpers"
import drop_tables from require "lapis.spec.db"

import Model, enum from require "lapis.db.mysql.model"
import types, create_table from require "lapis.db.mysql.schema"

assert_same_rows = (a, b) ->
  a = {k,v for k,v in pairs a}
  b = {k,v for k,v in pairs b}

  a.created_at = nil
  a.updated_at = nil

  b.created_at = nil
  b.updated_at = nil

  assert.same a, b

class Users extends Model
  @create_table: =>
    drop_tables @
    create_table @table_name!, {
      {"id", types.id}
      {"name", types.text}
    }

class Posts extends Model
  @timestamp: true

  @create_table: =>
    drop_tables @
    create_table @table_name!, {
      {"id", types.id}
      {"user_id", types.integer null: true}
      {"title", types.text null: false}
      {"body", types.text null: false}
      {"created_at", types.datetime}
      {"updated_at", types.datetime}
    }

class Likes extends Model
  @primary_key: {"user_id", "post_id"}
  @timestamp: true

  @relations: {
    {"user", belongs_to: "Users"}
    {"post", belongs_to: "Posts"}
  }

  @create_table: =>
    drop_tables @
    create_table @table_name!, {
      {"user_id", types.integer}
      {"post_id", types.integer}
      {"count", types.integer}
      {"created_at", types.datetime}
      {"updated_at", types.datetime}

      "PRIMARY KEY (user_id, post_id)"
    }


describe "model", ->
  setup ->
    setup_db!

  teardown ->
    teardown_db!

  describe "basic model", ->
    before_each ->
      Users\create_table!

    it "should find on empty table", ->
      nothing = Users\find 1
      assert.falsy nothing

    it "should insert new rows with autogenerated id", ->
      first = Users\create { name: "first" }
      second = Users\create { name: "second" }

      assert.same 1, first.id
      assert.same "first", first.name

      assert.same 2, second.id
      assert.same "second", second.name

      assert.same 2, Users\count!

    it "should get columns of model", ->
      assert.same {
        {
          "Extra": "auto_increment"
          "Field": "id"
          "Key": "PRI"
          "Null": "NO"
          "Type": "int(11)"
        }
        {
          "Extra": ""
          "Field": "name"
          "Key": ""
          "Null": "NO"
          "Type": "text"
        }
      }, Users\columns!

    describe "with some rows", ->
      local first, second

      before_each ->
        first = Users\create { name: "first" }
        second = Users\create { name: "second" }

      it "should should find existing row", ->
        assert.same first, Users\find first.id
        assert.same second, Users\find second.id
        assert.same second, Users\find name: "second"
        assert.falsy Users\find name: "second", id: 1
        assert.same first, Users\find id: "1"

      it "it should select rows", ->
        things = Users\select!
        assert.same 2, #things

        things = Users\select "order by name desc"
        assert "second", things[1].name
        assert "first", things[2].name

      it "it should only select specified fields", ->
        things = Users\select "order by id asc", fields: "id"
        assert.same {{id: 1}, {id: 2}}, things

      it "it should find all", ->
        things = Users\find_all {1,3}
        assert.same {first}, things

        things = Users\find_all {1,2}, where: {
          name: "second"
        }

        assert.same {second}, things

  describe "timestamp model", ->
    before_each ->
      Posts\create_table!

    it "should create empty row", ->
      -- this fails in postgres, but mysql gives default values
      Posts\create {}

    it "should create model", ->
      post = Posts\create {
        title: "Hello world"
        body: "Greetings"
      }

      assert.truthy post.created_at
      assert.truthy post.updated_at
      assert.same post.created_at, post.updated_at

    describe "with row", ->
      local post, other_post

      before_each ->
        post = Posts\create {
          title: "Hello world"
          body: "Greetings"
        }

        other_post = Posts\create {
          title: "Meetings"
          body: "Say all"
        }

      it "should update post", ->
        res = post\update {
          title: "Another world"
        }

        -- this is undocumented
        assert.same 1, res.affected_rows
        assert.same "Another world", post.title

      it "should delete post", ->
        assert.truthy (post\delete!)
        assert.falsy (post\delete!)
        assert.same {other_post}, Posts\select!

  describe "primary key model", ->
    before_each ->
      Likes\create_table!

    it "should find empty result by primary key", ->
      assert.falsy (Likes\find 1,2)

    it "should create", ->
      like = Likes\create {
        user_id: 40
        post_id: 22
        count: 1
      }

      assert.same 40, like.user_id
      assert.same 22, like.post_id

      assert.truthy like.created_at
      assert.truthy like.updated_at

      assert.same like, Likes\find 40, 22

    describe "with rows", ->
      local like, other_like

      before_each ->
        like = Likes\create {
          user_id: 1
          post_id: 2
          count: 1
        }

        other_like = Likes\create {
          user_id: 4
          post_id: 6
          count: 2
        }

      it "should delete row", ->
        like\delete!

        assert.has_error ->
          like\refresh!

        assert.same {other_like}, Likes\select!

      it "should update row", ->
        like\update {
          count: 5
        }

        assert.same 5, like.count

        assert_same_rows like, Likes\find(like.user_id, like.post_id)
        assert_same_rows other_like, Likes\find(other_like.user_id, other_like.post_id)


  describe "relations", ->
    before_each ->
      Users\create_table!
      Posts\create_table!
      Likes\create_table!

      package.loaded.models = {
        :Users, :Posts, :Likes
      }

    after_each ->
      package.loaded.models = nil


    it "should fetch relation", ->
      user = Users\create { name: "yeah" }
      post = Posts\create {
        title: "hi"
        body: "quality writing"
      }

      Likes\create {
        user_id: user.id
        post_id: post.id
      }

      like = unpack Likes\select!

      assert.same user, like\get_user!
      assert.same post, like\get_post!

  describe "include_in", ->
    before_each ->
      Users\create_table!
      Posts\create_table!
      Likes\create_table!

    before_each ->
      for i=1,2
        user = Users\create { name: "first" }
        for i=1,2
          Posts\create {
            user_id: user.id
            title: "My great post"
            body: "This is about something"
          }

    it "should include users for posts", ->
      posts = Posts\select!
      Users\include_in posts, "user_id"
      for post in *posts
        assert post.user
        assert.same post.user.id, post.user_id

    it "should include flipped many posts for user", ->
      users = Users\select!
      Posts\include_in users, "user_id", {
        flip: true
        many: true
      }

      for user in *users
        assert user.posts
        assert.same 2, #user.posts

        for post in *user.posts
          assert.same user.id, post.user_id



