import MountWidget from 'discourse/components/mount-widget';

export default MountWidget.extend({
  widget: 'election-list',
  classNames: ['election-list-container'],

  buildArgs() {
    return {
      category: this.get('category')
    }
  }
})
