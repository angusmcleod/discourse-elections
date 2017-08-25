import { default as computed } from 'ember-addons/ember-computed-decorators';
import Category from 'discourse/models/category';
import { ajax } from 'discourse/lib/ajax';

export default Ember.Controller.extend({
  @computed('model.isNominated')
  prefix(isNominated) {
    return `election.nomination.${isNominated ? 'remove' : 'add'}.`;
  },

  @computed('model.categoryId')
  category(categoryId) {
    return Category.findById(categoryId).name;
  },

  actions: {
    toggleNomination() {
      const topicId = this.get('model.topicId');
      const type = this.get('model.isNominated') ? 'DELETE' : 'POST';
      const callback = this.get('model.callback');

      this.set('loading', true);
      ajax('/election/nomination', {
        type,
        data: {
          topic_id: topicId
        }
      }).then((result) => {
        this.set('loading', false);
        callback();
        this.send('closeModal');
      })
    }
  }
})
