export default Ember.Component.extend({
  actions: {
    save() {
      this.sendAction('save')
    }
  }
});
