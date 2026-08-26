Ext.define('SYNO.SDS.App.KomariAgent.Instance', {
    extend: 'SYNO.SDS.AppInstance',
    appWindowName: 'SYNO.SDS.App.KomariAgent.Main',
    constructor: function() {
        this.callParent(arguments);
    }
});

Ext.define('SYNO.SDS.App.KomariAgent.Main', {
    extend: 'SYNO.SDS.AppWindow',
    appInstance: null,

    constructor: function(cfg) {
        this.appInstance = cfg.appInstance;

        var config = Ext.apply({
            resizable: false,
            maximizable: true,
            minimizable: true,
            width: 860,
            height: 640,
            layout: 'fit',
            items: [
                new Ext.BoxComponent({
                    height: '100%',
                    html: '<iframe src="/webman/3rdparty/KomariAgent/index.html" frameborder="0" marginheight="0" marginwidth="0" width="100%" height="100%"></iframe>'
                })
            ]
        }, cfg);

        this.callParent([config]);
    }
});