%%%
%%% wfd_SUITE.erl
%%% Copyright (C) 2013 James Lee
%%% 
%%% This program is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program.  If not, see <http://www.gnu.org/licenses/>.
%%%

-module(wfd_SUITE).
-author("James Lee <jlee@thestaticvoid.com>").
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include("wfd.hrl").

all() -> [
    test_wfd_dish_photo_server,
    test_wfd_unit_server,
    test_wfd_user_server,
    test_wfd_dish_server
].

init_per_suite(Config) ->
    wfd_app:start(),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.


%%
%% Test Cases
%%
test_wfd_dish_photo_server(Config) ->
    % Can add valid photos, but not anything else
    {error, processing_failed} = wfd_dish_photo_server:add_photo(filename:join(?config(data_dir, Config), "invalid-photo.jpg")),
    {ok, Uuid} = wfd_dish_photo_server:add_photo(filename:join(?config(data_dir, Config), "valid-photo.jpg")),

    % Can retrieve photos
    {ok, ThumbPhotoData} = wfd_dish_photo_server:get_photo(Uuid, thumb),
    {ok, FullPhotoData} = wfd_dish_photo_server:get_photo(Uuid, full),

    % The converted photos are valid and the proper size
    ThumbPhoto = filename:join(?config(priv_dir, Config), "thumb.jpg"),
    FullPhoto = filename:join(?config(priv_dir, Config), "full.jpg"),
    ok = file:write_file(ThumbPhoto, ThumbPhotoData),
    ok = file:write_file(FullPhoto, FullPhotoData),
    true = string:str(os:cmd("identify " ++ ThumbPhoto), "JPEG 240x240") > 0,
    true = string:str(os:cmd("identify " ++ FullPhoto), "JPEG 1000x667") > 0,

    % Removing the photo actually deletes it
    ok = wfd_dish_photo_server:remove_photo(Uuid),
    {error, no_such_photo} = wfd_dish_photo_server:get_photo(Uuid, thumb),
    {error, no_such_photo} = wfd_dish_photo_server:get_photo(Uuid, full).

test_wfd_unit_server(_Config) ->
    ok = eunit:test(wfd_unit_server, [verbose]).

test_wfd_user_server(_Config) ->
    {ok, FooUser1} = wfd_user_server:register_user("foo", "password", "foo@example.com"),
    {error, user_already_exists} = wfd_user_server:register_user("foo", "password", "foo@example.com"),
    {ok, BarUser1} = wfd_user_server:register_user("bar", "password", "foo@example.com"),

    % Validating email address requires valid token; and it adds the 'user' role
    [] = FooUser1#wfd_user.roles,
    {bad_validation_token, FooUser2} = wfd_user_server:validate_email("foo", "a-bad-validation-token"),
    {ok, FooUser3} = wfd_user_server:validate_email("foo", FooUser2#wfd_user.validation_token),
    already_validated = wfd_user_server:validate_email("foo", FooUser2#wfd_user.validation_token),
    [user] = FooUser3#wfd_user.roles,

    {error, email_already_registered} = wfd_user_server:register_user("baz", "password", "foo@example.com"),

    % Can change from an already validated email address to validate
    email_already_registered = wfd_user_server:validate_email("bar", BarUser1#wfd_user.validation_token),
    {ok, BarUser2} = wfd_user_server:update_email("bar", "bar@example.com"),
    {ok, _BarUser3} = wfd_user_server:validate_email("bar", BarUser2#wfd_user.validation_token),

    % TODO: Test authentication
    ok.

test_wfd_dish_server(Config) ->
    % A user can only have one dish by a name (case insensitive)
    ok = wfd_dish_server:new_dish("Foo Dish", "foo"),
    {error, dish_already_exists} = wfd_dish_server:new_dish("fOo DiSh", "foo"),
    ok = wfd_dish_server:new_dish("Foo Dish", "bar"),

    % Can set and get photo
    {error, no_photo} = wfd_dish_server:get_photo("Foo Dish", "foo", thumb),
    {error, processing_failed} = wfd_dish_server:change_photo("Foo Dish", "foo", filename:join(?config(data_dir, Config), "invalid-photo.jpg")),
    ok = wfd_dish_server:change_photo("Foo Dish", "foo", filename:join(?config(data_dir, Config), "valid-photo.jpg")),
    {ok, Photo1Uuid, _Photo1} = wfd_dish_server:get_photo("Foo Dish", "foo", thumb),

    % Changing photo deletes old photo from store
    ok = wfd_dish_server:change_photo("Foo Dish", "foo", filename:join(?config(data_dir, Config), "valid-photo.jpg")),
    {ok, Photo2Uuid, _Photo2} = wfd_dish_server:get_photo("Foo Dish", "foo", thumb),
    true = Photo1Uuid =/= Photo2Uuid,
    {error, no_such_photo} = wfd_dish_photo_server:get_photo(Photo1Uuid, thumb),

    % Deleting a dish deletes the photo from the photo store
    ok = wfd_dish_server:change_photo("Foo Dish", "bar", filename:join(?config(data_dir, Config), "valid-photo.jpg")),
    {ok, Photo3Uuid, _Photo3} = wfd_dish_server:get_photo("Foo Dish", "bar", thumb),
    ok = wfd_dish_server:delete_dish("Foo Dish", "bar"),
    {error, no_such_photo} = wfd_dish_photo_server:get_photo(Photo3Uuid, thumb),

    % TODO: Test ingredients
    ok.
