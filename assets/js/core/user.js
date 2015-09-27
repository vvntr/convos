(function(window) {
  Convos.User = function(attrs) {
    if (attrs) this.update(attrs);
    riot.observable(this);
    this._conversations = {};
    this._connections = {};
    this._method = 'httpCachedGet';
  };

  var proto = Convos.User.prototype;

  // Define attributes
  mixin.base(proto, {
    avatar: function() { return ''; },
    email: function() { return ''; }
  });

  mixin.http(proto);

  // Make the next http method fetch fresh data from server
  proto.fresh = function() { this._method = 'httpGet'; return this; };

  // Add, get or delete a Convos.Connection object on client side
  // Get:        c = user.connection(protocol, name)
  // Add/Update: c = user.connection(protocol, name, attrs)
  proto.connection = function(protocol, name, attrs) {
    var c = this._autovivificate('_connections', protocol, name, null);
    if (attrs) {
      if (c) return c.update(attrs);
      attrs[name] = name;
      attrs[user] = this;
      c = new Convos.Connection(attrs);
      this._connections[protocol][name] = c;
      this.trigger('connection', c);
    }
    else if(!c) {
      c = new Convos.Connection({name: name, user: this});
    }
    return c;
  };

  // Get a list of Convos.Connection objects from backend
  // Use user.fresh().connections(function() { ... }) to get fresh data from server
  proto.connections = function(cb) {
    this[this._method](apiUrl('/connections'), {}, function(err, xhr) {
      var connections = [];
      if (!err) {
        xhr.responseJSON.connections.forEach(function(attrs) {
          var c = new Convos.Connection(attrs);
          connections.push(this.connection(c.protocol(), c.name(), attrs));
        }.bind(this));
      }
      cb.call(this, err, connections);
    });
    return this.tap('_method', 'httpCachedGet');
  };

  // Get or create a single Convos.ConversationXxx object on client side
  // Get: user.conversation(id)
  // Create/update: user.conversation(id, attrs)
  proto.conversation = function(id, attrs) {
    if (!id && typeof attrs == 'object') id = attrs.id;
    if (!attrs) return this._conversations[id];
    if (this._conversations[id]) return this._conversations[id].update(attrs);
    this._conversations[id] = new Convos[attrs.users ? 'ConversationRoom' : 'ConversationDirect'](attrs);
    this.trigger('conversation', this._conversations[id]);
    return this._conversations[id];
  };

  // Get a list of Convos.ConversationXxx objects from backend
  // Use user.fresh().conversations(function() { ... }) to get fresh data from server
  proto.conversations = function(cb) {
    this[this._method](apiUrl('/conversations'), {}, function(err, xhr) {
      if (!err) xhr.responseJSON.conversations.forEach(function(c) { this.conversation(false, c); }.bind(this));
      cb.call(this, err, $.map(this._conversations, function(v, k) { return v; }));
    });
    return this.tap('_method', 'httpCachedGet');
  };

  // Get user settings from server
  // Use user.fresh().load(function() { ... }) to get fresh data from server
  proto.load = function(cb) {
    this[this._method](apiUrl('/user'), {}, function(err, xhr) {
      if (err) return cb.call(this, err);
      this.update(xhr.responseJSON);
      cb.call(this, false);
    });
    return this.tap('_method', 'httpCachedGet');
  };

  // Log out the user
  proto.logout = function(cb) {
    this.httpGet(apiUrl('/user/logout'), {}, function(err, xhr) {
      if (err) return cb.call(this, err);
      this.email('');
      cb.call(this, false);
    });
  };

  // Delete a connection on server side and remove it from the user object
  proto.removeConnection = function(protocol, name, cb) {
    this.httpDelete(apiUrl(['connection', protocol, name]), {}, function(err, xhr) {
      if (err) return cb.call(this, err);
      try { delete this._connections[protocol][name]; } catch(e) { console.log(e); };
      cb.call(this, '');
    });
    return this.tap('_method', 'httpCachedGet');
  };

  // Write user settings to server
  proto.save = function(attrs, cb) {
    if (!cb) return Object.keys(attrs).forEach(function(k) { if (typeof this[k] == 'function') this[k](attrs[k]); }.bind(this));
    return this.httpPost(apiUrl('/user'), attrs, function(err, xhr) {
      if (err) return cb.call(this, err);
      this.update(attrs);
      cb.call(this, err);
    });
  };
})(window);